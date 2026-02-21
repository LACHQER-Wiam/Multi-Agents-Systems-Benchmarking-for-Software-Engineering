"""
Outils compatibles OpenAI pour l'agent LangChain.

- BashWorkspaceTool : exécute des commandes bash dans un répertoire fixe (workspace).
  Équivalent pour OpenAI du ClaudeBashToolMiddleware (Anthropic).
  Utile pour éditer des fichiers, lister des répertoires, lancer des scripts.
"""

import subprocess
from pathlib import Path
from typing import Type

from langchain_core.tools import BaseTool
from pydantic import BaseModel, Field


class BashWorkspaceInput(BaseModel):
    """Entrée pour l'outil bash : une seule commande à exécuter."""

    command: str = Field(description="The exact bash command to run (e.g. 'ls -la', 'cat file.py').")


class BashWorkspaceTool(BaseTool):
    """
    Exécute une commande bash dans un répertoire de travail fixe (workspace).

    Toutes les commandes sont lancées avec ce répertoire comme répertoire courant,
    ce qui limite la portée des actions (fichiers, scripts) au workspace.
    Compatible OpenAI : simple outil, aucun lien avec un fournisseur LLM.
    """

    name: str = "bash"
    description: str = (
        "Run a single bash command in the workspace directory. "
        "Use for editing files, listing directories, running scripts. "
        "Input: the exact bash command to run (e.g. 'ls -la', 'cat file.py')."
    )
    args_schema: Type[BaseModel] = BashWorkspaceInput
    workspace_root: str = Field(
        default="/workspace",
        description="Root directory where commands are executed.",
    )
    timeout_seconds: int = Field(default=60, description="Max execution time per command.")

    def _run(self, command: str) -> str:
        """Execute the bash command in the workspace directory."""
        root = Path(self.workspace_root).resolve()
        if not root.is_dir():
            return f"Error: workspace directory does not exist: {root}"

        try:
            result = subprocess.run(
                ["bash", "-c", command],
                cwd=str(root),
                capture_output=True,
                text=True,
                timeout=self.timeout_seconds,
            )
        except subprocess.TimeoutExpired:
            return f"Error: command timed out after {self.timeout_seconds}s"

        stdout = result.stdout or ""
        stderr = result.stderr or ""
        if result.returncode != 0:
            return f"Exit code {result.returncode}\nstdout:\n{stdout}\nstderr:\n{stderr}"
        return stdout.strip() or "(no output)"

    async def _arun(self, command: str) -> str:
        """Async not implemented; falls back to sync run."""
        return self._run(command)
