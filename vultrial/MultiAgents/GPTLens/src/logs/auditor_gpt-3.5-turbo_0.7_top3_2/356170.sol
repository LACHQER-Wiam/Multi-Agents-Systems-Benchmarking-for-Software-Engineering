[
    {
        "function_name": "build_dirs",
        "code": "static void build_dirs(char *src, char *dst, size_t src_prefix_len, size_t dst_prefix_len) {\n\tchar *p = src + src_prefix_len + 1;\n\tchar *q = dst + dst_prefix_len + 1;\n\tchar *r = dst + dst_prefix_len;\n\tstruct stat s;\n\tbool last = false;\n\t*r = '\\0';\n\tfor (; !last; p++, q++) {\n\t\tif (*p == '\\0') {\n\t\t\tlast = true;\n\t\t}\n\t\tif (*p == '\\0' || (*p == '/' && *(p - 1) != '/')) {\n\t\t\t*p = '\\0';\n\t\t\tif (stat(src, &s) == 0 && S_ISDIR(s.st_mode)) {\n\t\t\t\t*q = '\\0';\n\t\t\t\t*r = '/';\n\t\t\t\tr = q;\n\t\t\t\tif (mkdir(dst, 0700) != 0 && errno != EEXIST)\n\t\t\t\t\terrExit(\"mkdir\");\n\t\t\t\tif (chmod(dst, s.st_mode) != 0)\n\t\t\t\t\terrExit(\"chmod\");\n\t\t\t}\n\t\t\tif (!last) {\n\t\t\t\t*p = '/';\n\t\t\t}\n\t\t}\n\t}\n}",
        "vulnerability": "Directory Traversal",
        "reason": "The code does not properly sanitize user input, allowing an attacker to manipulate the 'src' and 'dst' paths. By providing a malicious input, an attacker can traverse through directories and create or modify files outside the intended directory structure.",
        "file_name": "356170.sol"
    },
    {
        "function_name": "build_dirs",
        "code": "static void build_dirs(char *src, char *dst, size_t src_prefix_len, size_t dst_prefix_len) {\n\tchar *p = src + src_prefix_len + 1;\n\tchar *q = dst + dst_prefix_len + 1;\n\tchar *r = dst + dst_prefix_len;\n\tstruct stat s;\n\tbool last = false;\n\t*r = '\\0';\n\tfor (; !last; p++, q++) {\n\t\tif (*p == '\\0') {\n\t\t\tlast = true;\n\t\t}\n\t\tif (*p == '\\0' || (*p == '/' && *(p - 1) != '/')) {\n\t\t\t*p = '\\0';\n\t\t\tif (stat(src, &s) == 0 && S_ISDIR(s.st_mode)) {\n\t\t\t\t*q = '\\0';\n\t\t\t\t*r = '/';\n\t\t\t\tr = q;\n\t\t\t\tif (mkdir(dst, 0700) != 0 && errno != EEXIST)\n\t\t\t\t\terrExit(\"mkdir\");\n\t\t\t\tif (chmod(dst, s.st_mode) != 0)\n\t\t\t\t\terrExit(\"chmod\");\n\t\t\t}\n\t\t\tif (!last) {\n\t\t\t\t*p = '/';\n\t\t\t}\n\t\t}\n\t}\n}",
        "vulnerability": "Insecure Permissions",
        "reason": "The code creates directories with permissions set to 0700 without considering the potential risks. This can lead to sensitive data exposure or unauthorized access if the directories are created with overly permissive permissions. Attackers can exploit this vulnerability to gain access to confidential information.",
        "file_name": "356170.sol"
    },
    {
        "function_name": "build_dirs",
        "code": "static void build_dirs(char *src, char *dst, size_t src_prefix_len, size_t dst_prefix_len) {\n\tchar *p = src + src_prefix_len + 1;\n\tchar *q = dst + dst_prefix_len + 1;\n\tchar *r = dst + dst_prefix_len;\n\tstruct stat s;\n\tbool last = false;\n\t*r = '\\0';\n\tfor (; !last; p++, q++) {\n\t\tif (*p == '\\0') {\n\t\t\tlast = true;\n\t\t}\n\t\tif (*p == '\\0' || (*p == '/' && *(p - 1) != '/')) {\n\t\t\t*p = '\\0';\n\t\t\tif (stat(src, &s) == 0 && S_ISDIR(s.st_mode)) {\n\t\t\t\t*q = '\\0';\n\t\t\t\t*r = '/';\n\t\t\t\tr = q;\n\t\t\t\tif (mkdir(dst, 0700) != 0 && errno != EEXIST)\n\t\t\t\t\terrExit(\"mkdir\");\n\t\t\t\tif (chmod(dst, s.st_mode) != 0)\n\t\t\t\t\terrExit(\"chmod\");\n\t\t\t}\n\t\t\tif (!last) {\n\t\t\t\t*p = '/';\n\t\t\t}\n\t\t}\n\t}\n}",
        "vulnerability": "TOCTOU Race Condition",
        "reason": "The code first checks if the directory exists using 'stat' and then attempts to create it with 'mkdir'. This time-of-check-to-time-of-use (TOCTOU) vulnerability can be exploited by an attacker to change the file system between the 'stat' and 'mkdir' calls, leading to unexpected behavior or security breaches.",
        "file_name": "356170.sol"
    },
    {
        "function_name": "build_dirs",
        "code": "static void build_dirs(char *src, char *dst, size_t src_prefix_len, size_t dst_prefix_len) {\n\tchar *p = src + src_prefix_len + 1;\n\tchar *q = dst + dst_prefix_len + 1;\n\tchar *r = dst + dst_prefix_len;\n\tstruct stat s;\n\tbool last = false;\n\t*r = '\\0';\n\tfor (; !last; p++, q++) {\n\t\tif (*p == '\\0') {\n\t\t\tlast = true;\n\t\t}\n\t\tif (*p == '\\0' || (*p == '/' && *(p - 1) != '/')) {\n\t\t\t*p = '\\0';\n\t\t\tif (stat(src, &s) == 0 && S_ISDIR(s.st_mode)) {\n\t\t\t\t*q = '\\0';\n\t\t\t\t*r = '/';\n\t\t\t\tr = q;\n\t\t\t\tif (mkdir(dst, 0700) != 0 && errno != EEXIST)\n\t\t\t\t\terrExit(\"mkdir\");\n\t\t\t\tif (chmod(dst, s.st_mode) != 0)\n\t\t\t\t\terrExit(\"chmod\");\n\t\t\t}\n\t\t\tif (!last) {\n\t\t\t\t*p = '/';\n\t\t\t}\n\t\t}\n\t}\n}",
        "vulnerability": "Directory Traversal",
        "reason": "The code does not properly validate the input source directory (src) and destination directory (dst) paths, allowing an attacker to navigate outside the intended directories and access sensitive system files by manipulating the path input.",
        "file_name": "356170.sol"
    },
    {
        "function_name": "build_dirs",
        "code": "static void build_dirs(char *src, char *dst, size_t src_prefix_len, size_t dst_prefix_len) {\n\tchar *p = src + src_prefix_len + 1;\n\tchar *q = dst + dst_prefix_len + 1;\n\tchar *r = dst + dst_prefix_len;\n\tstruct stat s;\n\tbool last = false;\n\t*r = '\\0';\n\tfor (; !last; p++, q++) {\n\t\tif (*p == '\\0') {\n\t\t\tlast = true;\n\t\t}\n\t\tif (*p == '\\0' || (*p == '/' && *(p - 1) != '/')) {\n\t\t\t*p = '\\0';\n\t\t\tif (stat(src, &s) == 0 && S_ISDIR(s.st_mode)) {\n\t\t\t\t*q = '\\0';\n\t\t\t\t*r = '/';\n\t\t\t\tr = q;\n\t\t\t\tif (mkdir(dst, 0700) != 0 && errno != EEXIST)\n\t\t\t\t\terrExit(\"mkdir\");\n\t\t\t\tif (chmod(dst, s.st_mode) != 0)\n\t\t\t\t\terrExit(\"chmod\");\n\t\t\t}\n\t\t\tif (!last) {\n\t\t\t\t*p = '/';\n\t\t\t}\n\t\t}\n\t}\n}",
        "vulnerability": "Path Manipulation",
        "reason": "The code does not properly sanitize the input paths, allowing an attacker to manipulate the path by inserting or altering path separators, potentially leading to file system manipulation or unauthorized access to critical files.",
        "file_name": "356170.sol"
    },
    {
        "function_name": "build_dirs",
        "code": "static void build_dirs(char *src, char *dst, size_t src_prefix_len, size_t dst_prefix_len) {\n\tchar *p = src + src_prefix_len + 1;\n\tchar *q = dst + dst_prefix_len + 1;\n\tchar *r = dst + dst_prefix_len;\n\tstruct stat s;\n\tbool last = false;\n\t*r = '\\0';\n\tfor (; !last; p++, q++) {\n\t\tif (*p == '\\0') {\n\t\t\tlast = true;\n\t\t}\n\t\tif (*p == '\\0' || (*p == '/' && *(p - 1) != '/')) {\n\t\t\t*p = '\\0';\n\t\t\tif (stat(src, &s) == 0 && S_ISDIR(s.st_mode)) {\n\t\t\t\t*q = '\\0';\n\t\t\t\t*r = '/';\n\t\t\t\tr = q;\n\t\t\t\tif (mkdir(dst, 0700) != 0 && errno != EEXIST)\n\t\t\t\t\terrExit(\"mkdir\");\n\t\t\t\tif (chmod(dst, s.st_mode) != 0)\n\t\t\t\t\terrExit(\"chmod\");\n\t\t\t}\n\t\t\tif (!last) {\n\t\t\t\t*p = '/';\n\t\t\t}\n\t\t}\n\t}\n}",
        "vulnerability": "Insecure Permissions",
        "reason": "The code creates directories with insecure permissions (0700) without considering the security implications. This could allow an attacker to create directories with excessive permissions, potentially exposing sensitive data or allowing unauthorized access to the directories.",
        "file_name": "356170.sol"
    }
]