[
    {
        "function_name": "saveAs",
        "code": "int HttpFileImpl::saveAs(const std::string &fileName) const\n{\n    assert(!fileName.empty());\n    filesystem::path fsFileName(utils::toNativePath(fileName));\n    if (!fsFileName.is_absolute() && (!fsFileName.has_parent_path() ||\n                                      (fsFileName.begin()->string() != \".\" &&\n                                       fsFileName.begin()->string() != \"..\")))\n    {\n        filesystem::path fsUploadPath(utils::toNativePath(\n            HttpAppFrameworkImpl::instance().getUploadPath()));\n        fsFileName = fsUploadPath / fsFileName;\n    }\n    if (fsFileName.has_parent_path() &&\n        !filesystem::exists(fsFileName.parent_path()))\n    {\n        LOG_TRACE << \"create path:\" << fsFileName.parent_path();\n        drogon::error_code err;\n        filesystem::create_directories(fsFileName.parent_path(), err);\n        if (err)\n        {\n            LOG_SYSERR;\n            return -1;\n        }\n    }\n    return saveTo(fsFileName);\n}",
        "vulnerability": "Path Traversal",
        "reason": "The code uses the user-provided filename without proper validation to construct a file path. An attacker can manipulate the input filename to traverse directories and access sensitive files outside the intended directory.",
        "file_name": "250692.sol"
    },
    {
        "function_name": "saveAs",
        "code": "int HttpFileImpl::saveAs(const std::string &fileName) const\n{\n    assert(!fileName.empty());\n    filesystem::path fsFileName(utils::toNativePath(fileName));\n    if (!fsFileName.is_absolute() && (!fsFileName.has_parent_path() ||\n                                      (fsFileName.begin()->string() != \".\" &&\n                                       fsFileName.begin()->string() != \"..\")))\n    {\n        filesystem::path fsUploadPath(utils::toNativePath(\n            HttpAppFrameworkImpl::instance().getUploadPath()));\n        fsFileName = fsUploadPath / fsFileName;\n    }\n    if (fsFileName.has_parent_path() &&\n        !filesystem::exists(fsFileName.parent_path()))\n    {\n        LOG_TRACE << \"create path:\" << fsFileName.parent_path();\n        drogon::error_code err;\n        filesystem::create_directories(fsFileName.parent_path(), err);\n        if (err)\n        {\n            LOG_SYSERR;\n            return -1;\n        }\n    }\n    return saveTo(fsFileName);\n}",
        "vulnerability": "Directory Traversal",
        "reason": "The code constructs a new directory path based on the user-provided filename without proper validation. This can allow an attacker to create directories in unintended locations on the filesystem.",
        "file_name": "250692.sol"
    },
    {
        "function_name": "saveAs",
        "code": "int HttpFileImpl::saveAs(const std::string &fileName) const\n{\n    assert(!fileName.empty());\n    filesystem::path fsFileName(utils::toNativePath(fileName));\n    if (!fsFileName.is_absolute() && (!fsFileName.has_parent_path() ||\n                                      (fsFileName.begin()->string() != \".\" &&\n                                       fsFileName.begin()->string() != \"..\")))\n    {\n        filesystem::path fsUploadPath(utils::toNativePath(\n            HttpAppFrameworkImpl::instance().getUploadPath()));\n        fsFileName = fsUploadPath / fsFileName;\n    }\n    if (fsFileName.has_parent_path() &&\n        !filesystem::exists(fsFileName.parent_path()))\n    {\n        LOG_TRACE << \"create path:\" << fsFileName.parent_path();\n        drogon::error_code err;\n        filesystem::create_directories(fsFileName.parent_path(), err);\n        if (err)\n        {\n            LOG_SYSERR;\n            return -1;\n        }\n    }\n    return saveTo(fsFileName);\n}",
        "vulnerability": "Insecure File Handling",
        "reason": "The code does not properly sanitize the user-provided filename, which can lead to various file handling vulnerabilities such as overwriting critical files or executing arbitrary code by uploading malicious files.",
        "file_name": "250692.sol"
    },
    {
        "function_name": "saveAs",
        "code": "int HttpFileImpl::saveAs(const std::string &fileName) const\n{\n    assert(!fileName.empty());\n    filesystem::path fsFileName(utils::toNativePath(fileName));\n    if (!fsFileName.is_absolute() && (!fsFileName.has_parent_path() ||\n                                      (fsFileName.begin()->string() != \".\" &&\n                                       fsFileName.begin()->string() != \"..\")))\n    {\n        filesystem::path fsUploadPath(utils::toNativePath(\n            HttpAppFrameworkImpl::instance().getUploadPath()));\n        fsFileName = fsUploadPath / fsFileName;\n    }\n    if (fsFileName.has_parent_path() &&\n        !filesystem::exists(fsFileName.parent_path()))\n    {\n        LOG_TRACE << \"create path:\" << fsFileName.parent_path();\n        drogon::error_code err;\n        filesystem::create_directories(fsFileName.parent_path(), err);\n        if (err)\n        {\n            LOG_SYSERR;\n            return -1;\n        }\n    }\n    return saveTo(fsFileName);\n}",
        "vulnerability": "Path Traversal",
        "reason": "The code uses the user-provided filename to create a path without proper validation. An attacker can manipulate the filename to traverse directories and potentially access sensitive files outside the intended directory. For example, an attacker could provide a filename like '../../../etc/passwd' to access the system password file.",
        "file_name": "250692.sol"
    },
    {
        "function_name": "saveAs",
        "code": "int HttpFileImpl::saveAs(const std::string &fileName) const\n{\n    assert(!fileName.empty());\n    filesystem::path fsFileName(utils::toNativePath(fileName));\n    if (!fsFileName.is_absolute() && (!fsFileName.has_parent_path() ||\n                                      (fsFileName.begin()->string() != \".\" &&\n                                       fsFileName.begin()->string() != \"..\")))\n    {\n        filesystem::path fsUploadPath(utils::toNativePath(\n            HttpAppFrameworkImpl::instance().getUploadPath()));\n        fsFileName = fsUploadPath / fsFileName;\n    }\n    if (fsFileName.has_parent_path() &&\n        !filesystem::exists(fsFileName.parent_path()))\n    {\n        LOG_TRACE << \"create path:\" << fsFileName.parent_path();\n        drogon::error_code err;\n        filesystem::create_directories(fsFileName.parent_path(), err);\n        if (err)\n        {\n            LOG_SYSERR;\n            return -1;\n        }\n    }\n    return saveTo(fsFileName);\n}",
        "vulnerability": "Insecure File Permissions",
        "reason": "The code creates directories and saves files without explicitly setting secure permissions. This can lead to potential file permission vulnerabilities, allowing unauthorized users to read, write, or execute files within the directory. Attackers could exploit this to modify critical files or execute malicious scripts.",
        "file_name": "250692.sol"
    },
    {
        "function_name": "saveAs",
        "code": "int HttpFileImpl::saveAs(const std::string &fileName) const\n{\n    assert(!fileName.empty());\n    filesystem::path fsFileName(utils::toNativePath(fileName));\n    if (!fsFileName.is_absolute() && (!fsFileName.has_parent_path() ||\n                                      (fsFileName.begin()->string() != \".\" &&\n                                       fsFileName.begin()->string() != \"..\")))\n    {\n        filesystem::path fsUploadPath(utils::toNativePath(\n            HttpAppFrameworkImpl::instance().getUploadPath()));\n        fsFileName = fsUploadPath / fsFileName;\n    }\n    if (fsFileName.has_parent_path() &&\n        !filesystem::exists(fsFileName.parent_path()))\n    {\n        LOG_TRACE << \"create path:\" << fsFileName.parent_path();\n        drogon::error_code err;\n        filesystem::create_directories(fsFileName.parent_path(), err);\n        if (err)\n        {\n            LOG_SYSERR;\n            return -1;\n        }\n    }\n    return saveTo(fsFileName);\n}",
        "vulnerability": "Arbitrary File Upload",
        "reason": "The code allows users to specify the filename for saving files without proper validation. This can be exploited by attackers to upload arbitrary files, including malicious scripts or executable files, which can then be executed on the server to gain unauthorized access or perform further attacks.",
        "file_name": "250692.sol"
    }
]