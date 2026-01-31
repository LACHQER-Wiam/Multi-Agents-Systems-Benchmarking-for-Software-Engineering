[
    {
        "function_name": "build_dirs",
        "code": "static void build_dirs(char *src, char *dst, size_t src_prefix_len, size_t dst_prefix_len) {\n\tchar *p = src + src_prefix_len + 1;\n\tchar *q = dst + dst_prefix_len + 1;\n\tchar *r = dst + dst_prefix_len;\n\tstruct stat s;\n\tbool last = false;\n\t*r = '\\0';\n\tfor (; !last; p++, q++) {\n\t\tif (*p == '\\0') {\n\t\t\tlast = true;\n\t\t}\n\t\tif (*p == '\\0' || (*p == '/' && *(p - 1) != '/')) {\n\t\t\t*p = '\\0';\n\t\t\tif (stat(src, &s) == 0 && S_ISDIR(s.st_mode)) {\n\t\t\t\t*q = '\\0';\n\t\t\t\t*r = '/';\n\t\t\t\tr = q;\n\t\t\t\tmkdir_attr(dst, s.st_mode, 0, 0);\n\t\t\t}\n\t\t\tif (!last) {\n\t\t\t\t*p = '/';\n\t\t\t}\n\t\t}\n\t}\n}",
        "vulnerability": "Directory Traversal",
        "reason": "The code does not properly validate the source directory path before creating directories based on it, allowing an attacker to perform directory traversal attacks by manipulating the source path. This can lead to unauthorized access to sensitive files and directories outside of the intended scope.",
        "file_name": "204278.sol"
    },
    {
        "function_name": "build_dirs",
        "code": "static void build_dirs(char *src, char *dst, size_t src_prefix_len, size_t dst_prefix_len) {\n\tchar *p = src + src_prefix_len + 1;\n\tchar *q = dst + dst_prefix_len + 1;\n\tchar *r = dst + dst_prefix_len;\n\tstruct stat s;\n\tbool last = false;\n\t*r = '\\0';\n\tfor (; !last; p++, q++) {\n\t\tif (*p == '\\0') {\n\t\t\tlast = true;\n\t\t}\n\t\tif (*p == '\\0' || (*p == '/' && *(p - 1) != '/')) {\n\t\t\t*p = '\\0';\n\t\t\tif (stat(src, &s) == 0 && S_ISDIR(s.st_mode)) {\n\t\t\t\t*q = '\\0';\n\t\t\t\t*r = '/';\n\t\t\t\tr = q;\n\t\t\t\tmkdir_attr(dst, s.st_mode, 0, 0);\n\t\t\t}\n\t\t\tif (!last) {\n\t\t\t\t*p = '/';\n\t\t\t}\n\t\t}\n\t}\n}",
        "vulnerability": "Uncontrolled File System Modification",
        "reason": "The code blindly creates directories based on the source path without proper validation, allowing an attacker to manipulate the source path to create directories and potentially modify the file system in unexpected ways. This can lead to unauthorized changes to critical files and directories, disrupting the system's functionality or causing damage.",
        "file_name": "204278.sol"
    },
    {
        "function_name": "build_dirs",
        "code": "static void build_dirs(char *src, char *dst, size_t src_prefix_len, size_t dst_prefix_len) {\n\tchar *p = src + src_prefix_len + 1;\n\tchar *q = dst + dst_prefix_len + 1;\n\tchar *r = dst + dst_prefix_len;\n\tstruct stat s;\n\tbool last = false;\n\t*r = '\\0';\n\tfor (; !last; p++, q++) {\n\t\tif (*p == '\\0') {\n\t\t\tlast = true;\n\t\t}\n\t\tif (*p == '\\0' || (*p == '/' && *(p - 1) != '/')) {\n\t\t\t*p = '\\0';\n\t\t\tif (stat(src, &s) == 0 && S_ISDIR(s.st_mode)) {\n\t\t\t\t*q = '\\0';\n\t\t\t\t*r = '/';\n\t\t\t\tr = q;\n\t\t\t\tmkdir_attr(dst, s.st_mode, 0, 0);\n\t\t\t}\n\t\t\tif (!last) {\n\t\t\t\t*p = '/';\n\t\t\t}\n\t\t}\n\t}\n}",
        "vulnerability": "Insecure Permissions",
        "reason": "The code creates directories without explicitly setting secure permissions, potentially resulting in insecure directory permissions that could be exploited by an attacker. This can lead to unauthorized access, modification, or deletion of files within the created directories, compromising the system's integrity and confidentiality.",
        "file_name": "204278.sol"
    },
    {
        "function_name": "build_dirs",
        "code": "static void build_dirs(char *src, char *dst, size_t src_prefix_len, size_t dst_prefix_len) {\n\tchar *p = src + src_prefix_len + 1;\n\tchar *q = dst + dst_prefix_len + 1;\n\tchar *r = dst + dst_prefix_len;\n\tstruct stat s;\n\tbool last = false;\n\t*r = '\\0';\n\tfor (; !last; p++, q++) {\n\t\tif (*p == '\\0') {\n\t\t\tlast = true;\n\t\t}\n\t\tif (*p == '\\0' || (*p == '/' && *(p - 1) != '/')) {\n\t\t\t*p = '\\0';\n\t\t\tif (stat(src, &s) == 0 && S_ISDIR(s.st_mode)) {\n\t\t\t\t*q = '\\0';\n\t\t\t\t*r = '/';\n\t\t\t\tr = q;\n\t\t\t\tmkdir_attr(dst, s.st_mode, 0, 0);\n\t\t\t}\n\t\t\tif (!last) {\n\t\t\t\t*p = '/';\n\t\t\t}\n\t\t}\n\t}\n}",
        "vulnerability": "Directory Traversal Vulnerability",
        "reason": "The code does not properly sanitize user input in the 'src' parameter before using it to build the destination path. This allows an attacker to manipulate the 'src' parameter to traverse directories outside of the intended directory structure, potentially accessing sensitive files or directories on the system.",
        "file_name": "204278.sol"
    },
    {
        "function_name": "build_dirs",
        "code": "static void build_dirs(char *src, char *dst, size_t src_prefix_len, size_t dst_prefix_len) {\n\tchar *p = src + src_prefix_len + 1;\n\tchar *q = dst + dst_prefix_len + 1;\n\tchar *r = dst + dst_prefix_len;\n\tstruct stat s;\n\tbool last = false;\n\t*r = '\\0';\n\tfor (; !last; p++, q++) {\n\t\tif (*p == '\\0') {\n\t\t\tlast = true;\n\t\t}\n\t\tif (*p == '\\0' || (*p == '/' && *(p - 1) != '/')) {\n\t\t\t*p = '\\0';\n\t\t\tif (stat(src, &s) == 0 && S_ISDIR(s.st_mode)) {\n\t\t\t\t*q = '\\0';\n\t\t\t\t*r = '/';\n\t\t\t\tr = q;\n\t\t\t\tmkdir_attr(dst, s.st_mode, 0, 0);\n\t\t\t}\n\t\t\tif (!last) {\n\t\t\t\t*p = '/';\n\t\t\t}\n\t\t}\n\t}\n}",
        "vulnerability": "Incomplete Path Sanitization Vulnerability",
        "reason": "The code does not properly validate the input path before using it to create directories. This can lead to an attacker crafting a malicious path that could result in the creation of directories in unexpected locations, potentially causing a denial of service or allowing for the execution of arbitrary code.",
        "file_name": "204278.sol"
    },
    {
        "function_name": "build_dirs",
        "code": "static void build_dirs(char *src, char *dst, size_t src_prefix_len, size_t dst_prefix_len) {\n\tchar *p = src + src_prefix_len + 1;\n\tchar *q = dst + dst_prefix_len + 1;\n\tchar *r = dst + dst_prefix_len;\n\tstruct stat s;\n\tbool last = false;\n\t*r = '\\0';\n\tfor (; !last; p++, q++) {\n\t\tif (*p == '\\0') {\n\t\t\tlast = true;\n\t\t}\n\t\tif (*p == '\\0' || (*p == '/' && *(p - 1) != '/')) {\n\t\t\t*p = '\\0';\n\t\t\tif (stat(src, &s) == 0 && S_ISDIR(s.st_mode)) {\n\t\t\t\t*q = '\\0';\n\t\t\t\t*r = '/';\n\t\t\t\tr = q;\n\t\t\t\tmkdir_attr(dst, s.st_mode, 0, 0);\n\t\t\t}\n\t\t\tif (!last) {\n\t\t\t\t*p = '/';\n\t\t\t}\n\t\t}\n\t}\n}",
        "vulnerability": "Insecure Temporary Directory Creation Vulnerability",
        "reason": "The code uses the 'mkdir_attr' function to create directories without specifying secure permissions or ownership. This can allow an attacker to manipulate the 's.st_mode' parameter to create directories with insecure permissions, potentially leading to unauthorized access or modification of sensitive files.",
        "file_name": "204278.sol"
    }
]