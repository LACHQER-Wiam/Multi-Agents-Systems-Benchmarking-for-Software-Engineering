[
    {
        "function_name": "handle_PORT",
        "code": "static void handle_PORT(ctrl_t *ctrl, char *str)\n{\n\tint a, b, c, d, e, f;\n\tchar addr[INET_ADDRSTRLEN];\n\tstruct sockaddr_in sin;\n\tif (ctrl->data_sd > 0) {\n\t\tuev_io_stop(&ctrl->data_watcher);\n\t\tclose(ctrl->data_sd);\n\t\tctrl->data_sd = -1;\n\t}\n\tsscanf(str, \"%d,%d,%d,%d,%d,%d\", &a, &b, &c, &d, &e, &f);\n\tsnprintf(addr, sizeof(addr), \"%d.%d.%d.%d\", a, b, c, d);\n\tif (!inet_aton(addr, &(sin.sin_addr))) {\n\t\tERR(0, \"Invalid address '%s' given to PORT command\", addr);\n\t\tsend_msg(ctrl->sd, \"500 Illegal PORT command.\\r\\n\");\n\t\treturn;\n\t}\n\tstrlcpy(ctrl->data_address, addr, sizeof(ctrl->data_address));\n\tctrl->data_port = e * 256 + f;\n\tDBG(\"Client PORT command accepted for %s:%d\", ctrl->data_address, ctrl->data_port);\n\tsend_msg(ctrl->sd, \"200 PORT command successful.\\r\\n\");\n}",
        "vulnerability": "Buffer Overflow",
        "reason": "The 'addr' buffer is declared with a fixed size of INET_ADDRSTRLEN, but the snprintf function is used without proper bounds checking. An attacker could provide input that exceeds the buffer size, leading to a buffer overflow vulnerability.",
        "file_name": "273880.sol"
    },
    {
        "function_name": "handle_PORT",
        "code": "static void handle_PORT(ctrl_t *ctrl, char *str)\n{\n\tint a, b, c, d, e, f;\n\tchar addr[INET_ADDRSTRLEN];\n\tstruct sockaddr_in sin;\n\tif (ctrl->data_sd > 0) {\n\t\tuev_io_stop(&ctrl->data_watcher);\n\t\tclose(ctrl->data_sd);\n\t\tctrl->data_sd = -1;\n\t}\n\tsscanf(str, \"%d,%d,%d,%d,%d,%d\", &a, &b, &c, &d, &e, &f);\n\tsnprintf(addr, sizeof(addr), \"%d.%d.%d.%d\", a, b, c, d);\n\tif (!inet_aton(addr, &(sin.sin_addr))) {\n\t\tERR(0, \"Invalid address '%s' given to PORT command\", addr);\n\t\tsend_msg(ctrl->sd, \"500 Illegal PORT command.\\r\\n\");\n\t\treturn;\n\t}\n\tstrlcpy(ctrl->data_address, addr, sizeof(ctrl->data_address));\n\tctrl->data_port = e * 256 + f;\n\tDBG(\"Client PORT command accepted for %s:%d\", ctrl->data_address, ctrl->data_port);\n\tsend_msg(ctrl->sd, \"200 PORT command successful.\\r\\n\");\n}",
        "vulnerability": "Integer Overflow",
        "reason": "The calculation 'e * 256 + f' for 'ctrl->data_port' may result in an integer overflow if the values of 'e' and 'f' are not properly bounded. This can lead to unexpected behavior and potentially security vulnerabilities.",
        "file_name": "273880.sol"
    },
    {
        "function_name": "handle_PORT",
        "code": "static void handle_PORT(ctrl_t *ctrl, char *str)\n{\n\tint a, b, c, d, e, f;\n\tchar addr[INET_ADDRSTRLEN];\n\tstruct sockaddr_in sin;\n\tif (ctrl->data_sd > 0) {\n\t\tuev_io_stop(&ctrl->data_watcher);\n\t\tclose(ctrl->data_sd);\n\t\tctrl->data_sd = -1;\n\t}\n\tsscanf(str, \"%d,%d,%d,%d,%d,%d\", &a, &b, &c, &d, &e, &f);\n\tsnprintf(addr, sizeof(addr), \"%d.%d.%d.%d\", a, b, c, d);\n\tif (!inet_aton(addr, &(sin.sin_addr))) {\n\t\tERR(0, \"Invalid address '%s' given to PORT command\", addr);\n\t\tsend_msg(ctrl->sd, \"500 Illegal PORT command.\\r\\n\");\n\t\treturn;\n\t}\n\tstrlcpy(ctrl->data_address, addr, sizeof(ctrl->data_address));\n\tctrl->data_port = e * 256 + f;\n\tDBG(\"Client PORT command accepted for %s:%d\", ctrl->data_address, ctrl->data_port);\n\tsend_msg(ctrl->sd, \"200 PORT command successful.\\r\\n\");\n}",
        "vulnerability": "Input Validation",
        "reason": "The input provided in the 'str' parameter is directly used in the sscanf function without proper validation. This can lead to various issues such as buffer overflow, format string vulnerabilities, and more. It is crucial to validate and sanitize user input before processing it to prevent potential security risks.",
        "file_name": "273880.sol"
    },
    {
        "function_name": "handle_PORT",
        "code": "static void handle_PORT(ctrl_t *ctrl, char *str)\n{\n\tint a, b, c, d, e, f;\n\tchar addr[INET_ADDRSTRLEN];\n\tstruct sockaddr_in sin;\n\tif (ctrl->data_sd > 0) {\n\t\tuev_io_stop(&ctrl->data_watcher);\n\t\tclose(ctrl->data_sd);\n\t\tctrl->data_sd = -1;\n\t}\n\tsscanf(str, \"%d,%d,%d,%d,%d,%d\", &a, &b, &c, &d, &e, &f);\n\tsnprintf(addr, sizeof(addr), \"%d.%d.%d.%d\", a, b, c, d);\n\tif (!inet_aton(addr, &(sin.sin_addr))) {\n\t\tERR(0, \"Invalid address '%s' given to PORT command\", addr);\n\t\tsend_msg(ctrl->sd, \"500 Illegal PORT command.\\r\\n\");\n\t\treturn;\n\t}\n\tstrlcpy(ctrl->data_address, addr, sizeof(ctrl->data_address));\n\tctrl->data_port = e * 256 + f;\n\tDBG(\"Client PORT command accepted for %s:%d\", ctrl->data_address, ctrl->data_port);\n\tsend_msg(ctrl->sd, \"200 PORT command successful.\\r\\n\");\n}",
        "vulnerability": "Buffer Overflow",
        "reason": "The function uses sprintf to format the IP address into the 'addr' buffer without performing any bounds checking. This can lead to a buffer overflow if the input IP address is larger than the buffer size, potentially allowing an attacker to overwrite adjacent memory and execute arbitrary code.",
        "file_name": "273880.sol"
    },
    {
        "function_name": "handle_PORT",
        "code": "static void handle_PORT(ctrl_t *ctrl, char *str)\n{\n\tint a, b, c, d, e, f;\n\tchar addr[INET_ADDRSTRLEN];\n\tstruct sockaddr_in sin;\n\tif (ctrl->data_sd > 0) {\n\t\tuev_io_stop(&ctrl->data_watcher);\n\t\tclose(ctrl->data_sd);\n\t\tctrl->data_sd = -1;\n\t}\n\tsscanf(str, \"%d,%d,%d,%d,%d,%d\", &a, &b, &c, &d, &e, &f);\n\tsnprintf(addr, sizeof(addr), \"%d.%d.%d.%d\", a, b, c, d);\n\tif (!inet_aton(addr, &(sin.sin_addr))) {\n\t\tERR(0, \"Invalid address '%s' given to PORT command\", addr);\n\t\tsend_msg(ctrl->sd, \"500 Illegal PORT command.\\r\\n\");\n\t\treturn;\n\t}\n\tstrlcpy(ctrl->data_address, addr, sizeof(ctrl->data_address));\n\tctrl->data_port = e * 256 + f;\n\tDBG(\"Client PORT command accepted for %s:%d\", ctrl->data_address, ctrl->data_port);\n\tsend_msg(ctrl->sd, \"200 PORT command successful.\\r\\n\");\n}",
        "vulnerability": "Integer Overflow",
        "reason": "The calculation of 'ctrl->data_port = e * 256 + f' can potentially lead to an integer overflow if 'e' and 'f' are large values. This can result in a smaller than expected port number being assigned, which may allow an attacker to bypass port-based security measures and gain unauthorized access.",
        "file_name": "273880.sol"
    },
    {
        "function_name": "handle_PORT",
        "code": "static void handle_PORT(ctrl_t *ctrl, char *str)\n{\n\tint a, b, c, d, e, f;\n\tchar addr[INET_ADDRSTRLEN];\n\tstruct sockaddr_in sin;\n\tif (ctrl->data_sd > 0) {\n\t\tuev_io_stop(&ctrl->data_watcher);\n\t\tclose(ctrl->data_sd);\n\t\tctrl->data_sd = -1;\n\t}\n\tsscanf(str, \"%d,%d,%d,%d,%d,%d\", &a, &b, &c, &d, &e, &f);\n\tsnprintf(addr, sizeof(addr), \"%d.%d.%d.%d\", a, b, c, d);\n\tif (!inet_aton(addr, &(sin.sin_addr))) {\n\t\tERR(0, \"Invalid address '%s' given to PORT command\", addr);\n\t\tsend_msg(ctrl->sd, \"500 Illegal PORT command.\\r\\n\");\n\t\treturn;\n\t}\n\tstrlcpy(ctrl->data_address, addr, sizeof(ctrl->data_address));\n\tctrl->data_port = e * 256 + f;\n\tDBG(\"Client PORT command accepted for %s:%d\", ctrl->data_address, ctrl->data_port);\n\tsend_msg(ctrl->sd, \"200 PORT command successful.\\r\\n\");\n}",
        "vulnerability": "Input Validation",
        "reason": "The function does not perform sufficient input validation on the IP address provided in the 'str' parameter. This can lead to various security issues such as buffer overflows, denial of service, or even remote code execution if a malicious IP address is supplied by an attacker.",
        "file_name": "273880.sol"
    }
]