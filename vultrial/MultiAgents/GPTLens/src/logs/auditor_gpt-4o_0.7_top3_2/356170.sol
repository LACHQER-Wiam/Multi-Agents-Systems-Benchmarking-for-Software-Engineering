[
    {
        "function_name": "build_dirs",
        "code": "static void build_dirs(char *src, char *dst, size_t src_prefix_len, size_t dst_prefix_len) {\n\tchar *p = src + src_prefix_len + 1;\n\tchar *q = dst + dst_prefix_len + 1;\n\tchar *r = dst + dst_prefix_len;\n\tstruct stat s;\n\tbool last = false;\n\t*r = '\\0';\n\tfor (; !last; p++, q++) {\n\t\tif (*p == '\\0') {\n\t\t\tlast = true;\n\t\t}\n\t\tif (*p == '\\0' || (*p == '/' && *(p - 1) != '/')) {\n\t\t\t*p = '\\0';\n\t\t\tif (stat(src, &s) == 0 && S_ISDIR(s.st_mode)) {\n\t\t\t\t*q = '\\0';\n\t\t\t\t*r = '/';\n\t\t\t\tr = q;\n\t\t\t\tif (mkdir(dst, 0700) != 0 && errno != EEXIST)\n\t\t\t\t\terrExit(\"mkdir\");\n\t\t\t\tif (chmod(dst, s.st_mode) != 0)\n\t\t\t\t\terrExit(\"chmod\");\n\t\t\t}\n\t\t\tif (!last) {\n\t\t\t\t*p = '/';\n\t\t\t}\n\t\t}\n\t}\n}",
        "vulnerability": "Buffer overflow",
        "reason": "The code does not check for bounds when incrementing pointers 'p' and 'q'. If 'src' or 'dst' is not properly null-terminated or if the calculated lengths exceed the buffer size, this can lead to buffer overflow, potentially allowing attackers to overwrite adjacent memory.",
        "file_name": "356170.sol"
    },
    {
        "function_name": "build_dirs",
        "code": "static void build_dirs(char *src, char *dst, size_t src_prefix_len, size_t dst_prefix_len) {\n\tchar *p = src + src_prefix_len + 1;\n\tchar *q = dst + dst_prefix_len + 1;\n\tchar *r = dst + dst_prefix_len;\n\tstruct stat s;\n\tbool last = false;\n\t*r = '\\0';\n\tfor (; !last; p++, q++) {\n\t\tif (*p == '\\0') {\n\t\t\tlast = true;\n\t\t}\n\t\tif (*p == '\\0' || (*p == '/' && *(p - 1) != '/')) {\n\t\t\t*p = '\\0';\n\t\t\tif (stat(src, &s) == 0 && S_ISDIR(s.st_mode)) {\n\t\t\t\t*q = '\\0';\n\t\t\t\t*r = '/';\n\t\t\t\tr = q;\n\t\t\t\tif (mkdir(dst, 0700) != 0 && errno != EEXIST)\n\t\t\t\t\terrExit(\"mkdir\");\n\t\t\t\tif (chmod(dst, s.st_mode) != 0)\n\t\t\t\t\terrExit(\"chmod\");\n\t\t\t}\n\t\t\tif (!last) {\n\t\t\t\t*p = '/';\n\t\t\t}\n\t\t}\n\t}\n}",
        "vulnerability": "Time-of-check to time-of-use (TOCTOU) race condition",
        "reason": "There is a potential race condition between the 'stat' and 'mkdir' calls. An attacker can replace the directory after the 'stat' check but before 'mkdir' executes, possibly leading to unauthorized directory creation or privilege escalation.",
        "file_name": "356170.sol"
    },
    {
        "function_name": "build_dirs",
        "code": "static void build_dirs(char *src, char *dst, size_t src_prefix_len, size_t dst_prefix_len) {\n\tchar *p = src + src_prefix_len + 1;\n\tchar *q = dst + dst_prefix_len + 1;\n\tchar *r = dst + dst_prefix_len;\n\tstruct stat s;\n\tbool last = false;\n\t*r = '\\0';\n\tfor (; !last; p++, q++) {\n\t\tif (*p == '\\0') {\n\t\t\tlast = true;\n\t\t}\n\t\tif (*p == '\\0' || (*p == '/' && *(p - 1) != '/')) {\n\t\t\t*p = '\\0';\n\t\t\tif (stat(src, &s) == 0 && S_ISDIR(s.st_mode)) {\n\t\t\t\t*q = '\\0';\n\t\t\t\t*r = '/';\n\t\t\t\tr = q;\n\t\t\t\tif (mkdir(dst, 0700) != 0 && errno != EEXIST)\n\t\t\t\t\terrExit(\"mkdir\");\n\t\t\t\tif (chmod(dst, s.st_mode) != 0)\n\t\t\t\t\terrExit(\"chmod\");\n\t\t\t}\n\t\t\tif (!last) {\n\t\t\t\t*p = '/';\n\t\t\t}\n\t\t}\n\t}\n}",
        "vulnerability": "Improper file permissions",
        "reason": "The 'mkdir' function creates directories with a fixed permission (0700). If 's.st_mode' contains broader permissions, 'chmod' later expands these permissions, potentially allowing unauthorized access if the source directory is insecurely configured.",
        "file_name": "356170.sol"
    },
    {
        "function_name": "build_dirs",
        "code": "static void build_dirs(char *src, char *dst, size_t src_prefix_len, size_t dst_prefix_len) {\n\tchar *p = src + src_prefix_len + 1;\n\tchar *q = dst + dst_prefix_len + 1;\n\tchar *r = dst + dst_prefix_len;\n\tstruct stat s;\n\tbool last = false;\n\t*r = '\\0';\n\tfor (; !last; p++, q++) {\n\t\tif (*p == '\\0') {\n\t\t\tlast = true;\n\t\t}\n\t\tif (*p == '\\0' || (*p == '/' && *(p - 1) != '/')) {\n\t\t\t*p = '\\0';\n\t\t\tif (stat(src, &s) == 0 && S_ISDIR(s.st_mode)) {\n\t\t\t\t*q = '\\0';\n\t\t\t\t*r = '/';\n\t\t\t\tr = q;\n\t\t\t\tif (mkdir(dst, 0700) != 0 && errno != EEXIST)\n\t\t\t\t\terrExit(\"mkdir\");\n\t\t\t\tif (chmod(dst, s.st_mode) != 0)\n\t\t\t\t\terrExit(\"chmod\");\n\t\t\t}\n\t\t\tif (!last) {\n\t\t\t\t*p = '/';\n\t\t\t}\n\t\t}\n\t}\n}",
        "vulnerability": "Buffer Overflow",
        "reason": "The function does not check boundaries when incrementing pointers 'p' and 'q'. If 'src' or 'dst' are not properly null-terminated strings, or if they are shorter than expected, this can lead to accessing memory out of bounds, potentially causing a buffer overflow. This can be exploited by an attacker to execute arbitrary code or crash the program.",
        "file_name": "356170.sol"
    },
    {
        "function_name": "build_dirs",
        "code": "static void build_dirs(char *src, char *dst, size_t src_prefix_len, size_t dst_prefix_len) {\n\tchar *p = src + src_prefix_len + 1;\n\tchar *q = dst + dst_prefix_len + 1;\n\tchar *r = dst + dst_prefix_len;\n\tstruct stat s;\n\tbool last = false;\n\t*r = '\\0';\n\tfor (; !last; p++, q++) {\n\t\tif (*p == '\\0') {\n\t\t\tlast = true;\n\t\t}\n\t\tif (*p == '\\0' || (*p == '/' && *(p - 1) != '/')) {\n\t\t\t*p = '\\0';\n\t\t\tif (stat(src, &s) == 0 && S_ISDIR(s.st_mode)) {\n\t\t\t\t*q = '\\0';\n\t\t\t\t*r = '/';\n\t\t\t\tr = q;\n\t\t\t\tif (mkdir(dst, 0700) != 0 && errno != EEXIST)\n\t\t\t\t\terrExit(\"mkdir\");\n\t\t\t\tif (chmod(dst, s.st_mode) != 0)\n\t\t\t\t\terrExit(\"chmod\");\n\t\t\t}\n\t\t\tif (!last) {\n\t\t\t\t*p = '/';\n\t\t\t}\n\t\t}\n\t}\n}",
        "vulnerability": "Race Condition",
        "reason": "There is a time-of-check to time-of-use (TOCTOU) race condition between the 'stat' and 'mkdir'/'chmod' calls. An attacker could potentially replace the directory or alter permissions between these calls, leading to security vulnerabilities such as unauthorized access or privilege escalation.",
        "file_name": "356170.sol"
    },
    {
        "function_name": "build_dirs",
        "code": "static void build_dirs(char *src, char *dst, size_t src_prefix_len, size_t dst_prefix_len) {\n\tchar *p = src + src_prefix_len + 1;\n\tchar *q = dst + dst_prefix_len + 1;\n\tchar *r = dst + dst_prefix_len;\n\tstruct stat s;\n\tbool last = false;\n\t*r = '\\0';\n\tfor (; !last; p++, q++) {\n\t\tif (*p == '\\0') {\n\t\t\tlast = true;\n\t\t}\n\t\tif (*p == '\\0' || (*p == '/' && *(p - 1) != '/')) {\n\t\t\t*p = '\\0';\n\t\t\tif (stat(src, &s) == 0 && S_ISDIR(s.st_mode)) {\n\t\t\t\t*q = '\\0';\n\t\t\t\t*r = '/';\n\t\t\t\tr = q;\n\t\t\t\tif (mkdir(dst, 0700) != 0 && errno != EEXIST)\n\t\t\t\t\terrExit(\"mkdir\");\n\t\t\t\tif (chmod(dst, s.st_mode) != 0)\n\t\t\t\t\terrExit(\"chmod\");\n\t\t\t}\n\t\t\tif (!last) {\n\t\t\t\t*p = '/';\n\t\t\t}\n\t\t}\n\t}\n}",
        "vulnerability": "Improper Permission Handling",
        "reason": "The function uses 'chmod' to set permissions based on the source's permissions, which could inadvertently escalate privileges. If the source directory has weaker or more permissive settings than intended, copying those permissions could expose sensitive directories in 'dst' to unauthorized access.",
        "file_name": "356170.sol"
    }
]