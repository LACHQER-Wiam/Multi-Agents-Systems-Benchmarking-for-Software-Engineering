[
    {
        "function_name": "HttpFileImpl::save",
        "code": "int HttpFileImpl::save(const std::string &path) const\n{\n    assert(!path.empty());\n    if (fileName_.empty())\n        return -1;\n    filesystem::path fsPath(utils::toNativePath(path));\n    if (!fsPath.is_absolute() &&\n        (!fsPath.has_parent_path() ||\n         (fsPath.begin()->string() != \".\" && fsPath.begin()->string() != \"..\")))\n    {\n        filesystem::path fsUploadPath(utils::toNativePath(\n            HttpAppFrameworkImpl::instance().getUploadPath()));\n        fsPath = fsUploadPath / fsPath;\n    }\n    filesystem::path fsFileName(utils::toNativePath(fileName_));\n    if (!filesystem::exists(fsPath))\n    {\n        LOG_TRACE << \"create path:\" << fsPath;\n        drogon::error_code err;\n        filesystem::create_directories(fsPath, err);\n        if (err)\n        {\n            LOG_SYSERR;\n            return -1;\n        }\n    }\n    return saveTo(fsPath / fsFileName);\n}",
        "vulnerability": "Path Traversal",
        "reason": "The code uses the input 'path' directly without proper validation, which can lead to path traversal attacks. An attacker can potentially manipulate the path input to access files outside of the intended directory, leading to unauthorized file access or execution of arbitrary code.",
        "file_name": "197057.sol"
    },
    {
        "function_name": "HttpFileImpl::save",
        "code": "int HttpFileImpl::save(const std::string &path) const\n{\n    assert(!path.empty());\n    if (fileName_.empty())\n        return -1;\n    filesystem::path fsPath(utils::toNativePath(path));\n    if (!fsPath.is_absolute() &&\n        (!fsPath.has_parent_path() ||\n         (fsPath.begin()->string() != \".\" && fsPath.begin()->string() != \"..\")))\n    {\n        filesystem::path fsUploadPath(utils::toNativePath(\n            HttpAppFrameworkImpl::instance().getUploadPath()));\n        fsPath = fsUploadPath / fsPath;\n    }\n    filesystem::path fsFileName(utils::toNativePath(fileName_));\n    if (!filesystem::exists(fsPath))\n    {\n        LOG_TRACE << \"create path:\" << fsPath;\n        drogon::error_code err;\n        filesystem::create_directories(fsPath, err);\n        if (err)\n        {\n            LOG_SYSERR;\n            return -1;\n        }\n    }\n    return saveTo(fsPath / fsFileName);\n}",
        "vulnerability": "Insecure Direct Object Reference (IDOR)",
        "reason": "The code assumes that the 'path' provided by the user is safe and does not perform proper authorization checks. This can lead to an Insecure Direct Object Reference (IDOR) vulnerability where an attacker can manipulate the 'path' parameter to access or modify files that they are not authorized to, bypassing any access control mechanisms.",
        "file_name": "197057.sol"
    },
    {
        "function_name": "HttpFileImpl::save",
        "code": "int HttpFileImpl::save(const std::string &path) const\n{\n    assert(!path.empty());\n    if (fileName_.empty())\n        return -1;\n    filesystem::path fsPath(utils::toNativePath(path));\n    if (!fsPath.is_absolute() &&\n        (!fsPath.has_parent_path() ||\n         (fsPath.begin()->string() != \".\" && fsPath.begin()->string() != \"..\")))\n    {\n        filesystem::path fsUploadPath(utils::toNativePath(\n            HttpAppFrameworkImpl::instance().getUploadPath()));\n        fsPath = fsUploadPath / fsPath;\n    }\n    filesystem::path fsFileName(utils::toNativePath(fileName_));\n    if (!filesystem::exists(fsPath))\n    {\n        LOG_TRACE << \"create path:\" << fsPath;\n        drogon::error_code err;\n        filesystem::create_directories(fsPath, err);\n        if (err)\n        {\n            LOG_SYSERR;\n            return -1;\n        }\n    }\n    return saveTo(fsPath / fsFileName);\n}",
        "vulnerability": "Arbitrary File Upload",
        "reason": "The code allows the user to specify the 'path' where the file will be saved without proper validation. This can be exploited by an attacker to upload malicious files to the server, potentially leading to remote code execution or unauthorized access to sensitive information.",
        "file_name": "197057.sol"
    },
    {
        "function_name": "save",
        "code": "int HttpFileImpl::save(const std::string &path) const\n{\n    assert(!path.empty());\n    if (fileName_.empty())\n        return -1;\n    filesystem::path fsPath(utils::toNativePath(path));\n    if (!fsPath.is_absolute() &&\n        (!fsPath.has_parent_path() ||\n         (fsPath.begin()->string() != \".\" && fsPath.begin()->string() != \"..\")))\n    {\n        filesystem::path fsUploadPath(utils::toNativePath(\n            HttpAppFrameworkImpl::instance().getUploadPath()));\n        fsPath = fsUploadPath / fsPath;\n    }\n    filesystem::path fsFileName(utils::toNativePath(fileName_));\n    if (!filesystem::exists(fsPath))\n    {\n        LOG_TRACE << \"create path:\" << fsPath;\n        drogon::error_code err;\n        filesystem::create_directories(fsPath, err);\n        if (err)\n        {\n            LOG_SYSERR;\n            return -1;\n        }\n    }\n    return saveTo(fsPath / fsFileName);\n}",
        "vulnerability": "Path Traversal",
        "reason": "The code allows for path traversal vulnerability because the user-supplied 'path' parameter is directly used to construct the file path without proper validation. An attacker can manipulate the 'path' parameter to traverse directories and access sensitive files outside the intended directory.",
        "file_name": "197057.sol"
    },
    {
        "function_name": "save",
        "code": "int HttpFileImpl::save(const std::string &path) const\n{\n    assert(!path.empty());\n    if (fileName_.empty())\n        return -1;\n    filesystem::path fsPath(utils::toNativePath(path));\n    if (!fsPath.is_absolute() &&\n        (!fsPath.has_parent_path() ||\n         (fsPath.begin()->string() != \".\" && fsPath.begin()->string() != \"..\")))\n    {\n        filesystem::path fsUploadPath(utils::toNativePath(\n            HttpAppFrameworkImpl::instance().getUploadPath()));\n        fsPath = fsUploadPath / fsPath;\n    }\n    filesystem::path fsFileName(utils::toNativePath(fileName_));\n    if (!filesystem::exists(fsPath))\n    {\n        LOG_TRACE << \"create path:\" << fsPath;\n        drogon::error_code err;\n        filesystem::create_directories(fsPath, err);\n        if (err)\n        {\n            LOG_SYSERR;\n            return -1;\n        }\n    }\n    return saveTo(fsPath / fsFileName);\n}",
        "vulnerability": "Directory Traversal",
        "reason": "The code is vulnerable to directory traversal attack as it constructs the file path using the 'path' parameter without proper validation. An attacker can manipulate the 'path' parameter to traverse directories and access or modify files in unintended locations.",
        "file_name": "197057.sol"
    },
    {
        "function_name": "save",
        "code": "int HttpFileImpl::save(const std::string &path) const\n{\n    assert(!path.empty());\n    if (fileName_.empty())\n        return -1;\n    filesystem::path fsPath(utils::toNativePath(path));\n    if (!fsPath.is_absolute() &&\n        (!fsPath.has_parent_path() ||\n         (fsPath.begin()->string() != \".\" && fsPath.begin()->string() != \"..\")))\n    {\n        filesystem::path fsUploadPath(utils::toNativePath(\n            HttpAppFrameworkImpl::instance().getUploadPath()));\n        fsPath = fsUploadPath / fsPath;\n    }\n    filesystem::path fsFileName(utils::toNativePath(fileName_));\n    if (!filesystem::exists(fsPath))\n    {\n        LOG_TRACE << \"create path:\" << fsPath;\n        drogon::error_code err;\n        filesystem::create_directories(fsPath, err);\n        if (err)\n        {\n            LOG_SYSERR;\n            return -1;\n        }\n    }\n    return saveTo(fsPath / fsFileName);\n}",
        "vulnerability": "Insecure File Handling",
        "reason": "The code lacks proper validation and sanitization of user-supplied file paths, leading to insecure file handling. Attackers can exploit this vulnerability to read, write, or execute arbitrary files on the server, potentially causing data leakage or system compromise.",
        "file_name": "197057.sol"
    }
]