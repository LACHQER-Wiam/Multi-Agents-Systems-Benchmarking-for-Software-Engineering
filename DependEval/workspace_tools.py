"""
Outils pour agent ReAct quand l'input est un repo cloné sur disque (ex. GitHub).

Ces tools supposent qu'un répertoire workspace existe avec les fichiers du repo.
Ils ne sont pas adaptés au format actuel DependEval (JSON self-contained).
À utiliser quand le flux clone un repo GitHub dans WORKSPACE_ROOT.

- ReadFileTool : lire le contenu d'un fichier
- ListDirTool : lister les fichiers d'un répertoire
- SearchInFilesTool : chercher un motif dans les fichiers
- WriteFileTool : écrire dans un fichier
- ExtractImportsTool : extraire les imports d'un fichier Python
"""

import os
import re
from pathlib import Path
from typing import List, Type

from langchain_core.tools import BaseTool
from pydantic import BaseModel, Field


# -----------------------------------------------------------------------------
# Schémas d'entrée
# -----------------------------------------------------------------------------


class ReadFileInput(BaseModel):
    """Chemin relatif au workspace."""

    filepath: str = Field(description="Relative path to the file (e.g. 'src/main.py').")


class ListDirInput(BaseModel):
    """Chemin du répertoire à lister."""

    dirpath: str = Field(
        default=".",
        description="Relative path to the directory (e.g. 'src' or '.').",
    )
    recursive: bool = Field(
        default=False,
        description="If true, list recursively; otherwise only direct children.",
    )


class SearchInFilesInput(BaseModel):
    """Motif et options de recherche."""

    pattern: str = Field(description="Search pattern (text or regex).")
    file_glob: str = Field(
        default="*",
        description="Glob for file filter (e.g. '*.py', '*.js').",
    )
    dirpath: str = Field(
        default=".",
        description="Root directory to search in (relative to workspace).",
    )


class WriteFileInput(BaseModel):
    """Chemin et contenu à écrire."""

    filepath: str = Field(description="Relative path to the file.")
    content: str = Field(description="Content to write to the file.")


class ExtractImportsInput(BaseModel):
    """Chemin du fichier Python à analyser."""

    filepath: str = Field(description="Relative path to the Python file (e.g. 'src/module.py').")


# -----------------------------------------------------------------------------
# Helpers : sécurité (path dans workspace)
# -----------------------------------------------------------------------------


def _resolve_in_workspace(workspace_root: Path, rel_path: str) -> Path:
    """Resout un chemin relatif et vérifie qu'il reste dans le workspace."""
    root = workspace_root.resolve()
    path = (root / rel_path).resolve()
    if not str(path).startswith(str(root)):
        raise ValueError(f"Path escapes workspace: {rel_path}")
    return path


# -----------------------------------------------------------------------------
# Tools
# -----------------------------------------------------------------------------


class ReadFileTool(BaseTool):
    """
    Lit le contenu d'un fichier dans le workspace.

    Le chemin doit être relatif au workspace_root. Utile pour analyser du code
    sans tout charger dans le prompt.
    """

    name: str = "read_file"
    description: str = (
        "Read the content of a file in the workspace. "
        "Input: relative filepath (e.g. 'src/main.py')."
    )
    args_schema: Type[BaseModel] = ReadFileInput
    workspace_root: str = Field(default="/workspace", description="Workspace root directory.")

    def _run(self, filepath: str) -> str:
        root = Path(self.workspace_root).resolve()
        if not root.is_dir():
            return f"Error: workspace does not exist: {root}"

        try:
            path = _resolve_in_workspace(root, filepath)
        except ValueError as e:
            return str(e)

        if not path.is_file():
            return f"Error: not a file or not found: {filepath}"

        try:
            return path.read_text(encoding="utf-8", errors="replace")
        except Exception as e:
            return f"Error reading file: {e}"

    async def _arun(self, filepath: str) -> str:
        return self._run(filepath)


class ListDirTool(BaseTool):
    """
    Liste les fichiers et dossiers d'un répertoire.

    Utile pour explorer la structure du repo (où sont les .py, quels modules, etc.).
    """

    name: str = "list_dir"
    description: str = (
        "List files and directories in a folder. "
        "Input: dirpath (relative, e.g. '.' or 'src'), optional recursive=true."
    )
    args_schema: Type[BaseModel] = ListDirInput
    workspace_root: str = Field(default="/workspace", description="Workspace root directory.")

    def _run(self, dirpath: str = ".", recursive: bool = False) -> str:
        root = Path(self.workspace_root).resolve()
        if not root.is_dir():
            return f"Error: workspace does not exist: {root}"

        try:
            path = _resolve_in_workspace(root, dirpath)
        except ValueError as e:
            return str(e)

        if not path.is_dir():
            return f"Error: not a directory or not found: {dirpath}"

        lines: List[str] = []
        if recursive:
            for p in sorted(path.rglob("*")):
                rel = p.relative_to(path)
                prefix = "  " * (len(rel.parts) - 1)
                marker = "/" if p.is_dir() else ""
                lines.append(f"{prefix}{rel.name}{marker}")
        else:
            for p in sorted(path.iterdir()):
                marker = "/" if p.is_dir() else ""
                lines.append(f"{p.name}{marker}")

        return "\n".join(lines) if lines else "(empty)"

    async def _arun(self, dirpath: str = ".", recursive: bool = False) -> str:
        return self._run(dirpath, recursive)


class SearchInFilesTool(BaseTool):
    """
    Cherche un motif (texte ou regex) dans les fichiers du workspace.

    Utile pour "qui importe X ?", "où est appelée la fonction Y ?".
    """

    name: str = "search_in_files"
    description: str = (
        "Search for a pattern in workspace files. "
        "Input: pattern (text or regex), optional file_glob (e.g. '*.py'), optional dirpath."
    )
    args_schema: Type[BaseModel] = SearchInFilesInput
    workspace_root: str = Field(default="/workspace", description="Workspace root directory.")

    def _run(
        self,
        pattern: str,
        file_glob: str = "*",
        dirpath: str = ".",
    ) -> str:
        root = Path(self.workspace_root).resolve()
        if not root.is_dir():
            return f"Error: workspace does not exist: {root}"

        try:
            base = _resolve_in_workspace(root, dirpath)
        except ValueError as e:
            return str(e)

        if not base.is_dir():
            return f"Error: not a directory: {dirpath}"

        results: List[str] = []
        try:
            regex = re.compile(pattern)
        except re.error:
            regex = re.compile(re.escape(pattern))

        for fpath in base.rglob(file_glob):
            if not fpath.is_file():
                continue
            try:
                text = fpath.read_text(encoding="utf-8", errors="replace")
            except Exception:
                continue

            rel = fpath.relative_to(root)
            for i, line in enumerate(text.splitlines(), 1):
                if regex.search(line):
                    results.append(f"{rel}:{i}: {line.strip()}")

        if not results:
            return f"No matches for '{pattern}'"
        return "\n".join(results[:100])  # cap à 100 lignes


class WriteFileTool(BaseTool):
    """
    Écrit du contenu dans un fichier du workspace.

    Crée le fichier s'il n'existe pas, remplace le contenu sinon.
    Utile pour ME (Multi-file Editing) quand le repo est cloné.
    """

    name: str = "write_file"
    description: str = (
        "Write content to a file in the workspace. "
        "Input: filepath (relative), content."
    )
    args_schema: Type[BaseModel] = WriteFileInput
    workspace_root: str = Field(default="/workspace", description="Workspace root directory.")

    def _run(self, filepath: str, content: str) -> str:
        root = Path(self.workspace_root).resolve()
        if not root.is_dir():
            return f"Error: workspace does not exist: {root}"

        try:
            path = _resolve_in_workspace(root, filepath)
        except ValueError as e:
            return str(e)

        path.parent.mkdir(parents=True, exist_ok=True)
        try:
            path.write_text(content, encoding="utf-8")
            return f"Wrote {filepath}"
        except Exception as e:
            return f"Error writing file: {e}"

    async def _arun(self, filepath: str, content: str) -> str:
        return self._run(filepath, content)


class ExtractImportsTool(BaseTool):
    """
    Extrait les imports d'un fichier Python.

    Retourne une liste de modules/fichiers importés.
    Utile pour DR/RC (analyser les dépendances entre fichiers).
    """

    name: str = "extract_imports"
    description: str = (
        "Extract import statements from a Python file. "
        "Input: relative filepath (e.g. 'src/module.py')."
    )
    args_schema: Type[BaseModel] = ExtractImportsInput
    workspace_root: str = Field(default="/workspace", description="Workspace root directory.")

    def _run(self, filepath: str) -> str:
        root = Path(self.workspace_root).resolve()
        if not root.is_dir():
            return f"Error: workspace does not exist: {root}"

        try:
            path = _resolve_in_workspace(root, filepath)
        except ValueError as e:
            return str(e)

        if not path.is_file():
            return f"Error: not a file or not found: {filepath}"

        imports: List[str] = []
        import_re = re.compile(
            r"^\s*(?:from\s+(.+?)\s+)?import\s+(.+?)(?:\s+as\s+\w+)?\s*$"
        )

        try:
            text = path.read_text(encoding="utf-8", errors="replace")
        except Exception as e:
            return f"Error reading file: {e}"

        for line in text.splitlines():
            line = line.strip()
            if not line or line.startswith("#"):
                continue
            m = import_re.match(line)
            if m:
                from_part, import_part = m.groups()
                if from_part:
                    imports.append(f"from {from_part} import {import_part}")
                else:
                    imports.append(f"import {import_part}")

        return "\n".join(imports) if imports else "(no imports found)"

    async def _arun(self, filepath: str) -> str:
        return self._run(filepath)
