[
    {
        "function_name": "handle_PORT",
        "code": "static void handle_PORT(ctrl_t *ctrl, char *str)\n{\n\tint a, b, c, d, e, f;\n\tchar addr[INET_ADDRSTRLEN];\n\tstruct sockaddr_in sin;\n\tif (ctrl->data_sd > 0) {\n\t\tuev_io_stop(&ctrl->data_watcher);\n\t\tclose(ctrl->data_sd);\n\t\tctrl->data_sd = -1;\n\t}\n\tsscanf(str, \"%d,%d,%d,%d,%d,%d\", &a, &b, &c, &d, &e, &f);\n\tsprintf(addr, \"%d.%d.%d.%d\", a, b, c, d);\n\tif (!inet_aton(addr, &(sin.sin_addr))) {\n\t\tERR(0, \"Invalid address '%s' given to PORT command\", addr);\n\t\tsend_msg(ctrl->sd, \"500 Illegal PORT command.\\r\\n\");\n\t\treturn;\n\t}\n\tstrlcpy(ctrl->data_address, addr, sizeof(ctrl->data_address));\n\tctrl->data_port = e * 256 + f;\n\tDBG(\"Client PORT command accepted for %s:%d\", ctrl->data_address, ctrl->data_port);\n\tsend_msg(ctrl->sd, \"200 PORT command successful.\\r\\n\");\n}",
        "vulnerability": "Improper input validation",
        "reason": "The use of sscanf without proper bounds checking can lead to buffer overflow or incorrect parsing of input data. An attacker could provide a malformed string that causes sscanf to read beyond expected input, potentially leading to undefined behavior or memory corruption.",
        "file_name": "198399.sol"
    },
    {
        "function_name": "handle_PORT",
        "code": "static void handle_PORT(ctrl_t *ctrl, char *str)\n{\n\tint a, b, c, d, e, f;\n\tchar addr[INET_ADDRSTRLEN];\n\tstruct sockaddr_in sin;\n\tif (ctrl->data_sd > 0) {\n\t\tuev_io_stop(&ctrl->data_watcher);\n\t\tclose(ctrl->data_sd);\n\t\tctrl->data_sd = -1;\n\t}\n\tsscanf(str, \"%d,%d,%d,%d,%d,%d\", &a, &b, &c, &d, &e, &f);\n\tsprintf(addr, \"%d.%d.%d.%d\", a, b, c, d);\n\tif (!inet_aton(addr, &(sin.sin_addr))) {\n\t\tERR(0, \"Invalid address '%s' given to PORT command\", addr);\n\t\tsend_msg(ctrl->sd, \"500 Illegal PORT command.\\r\\n\");\n\t\treturn;\n\t}\n\tstrlcpy(ctrl->data_address, addr, sizeof(ctrl->data_address));\n\tctrl->data_port = e * 256 + f;\n\tDBG(\"Client PORT command accepted for %s:%d\", ctrl->data_address, ctrl->data_port);\n\tsend_msg(ctrl->sd, \"200 PORT command successful.\\r\\n\");\n}",
        "vulnerability": "Buffer overflow risk",
        "reason": "The use of sprintf without bounds checking can lead to a buffer overflow if the integers are large or if there are unexpected characters. This could allow an attacker to overwrite adjacent memory, leading to potential code execution or denial of service.",
        "file_name": "198399.sol"
    },
    {
        "function_name": "handle_PORT",
        "code": "static void handle_PORT(ctrl_t *ctrl, char *str)\n{\n\tint a, b, c, d, e, f;\n\tchar addr[INET_ADDRSTRLEN];\n\tstruct sockaddr_in sin;\n\tif (ctrl->data_sd > 0) {\n\t\tuev_io_stop(&ctrl->data_watcher);\n\t\tclose(ctrl->data_sd);\n\t\tctrl->data_sd = -1;\n\t}\n\tsscanf(str, \"%d,%d,%d,%d,%d,%d\", &a, &b, &c, &d, &e, &f);\n\tsprintf(addr, \"%d.%d.%d.%d\", a, b, c, d);\n\tif (!inet_aton(addr, &(sin.sin_addr))) {\n\t\tERR(0, \"Invalid address '%s' given to PORT command\", addr);\n\t\tsend_msg(ctrl->sd, \"500 Illegal PORT command.\\r\\n\");\n\t\treturn;\n\t}\n\tstrlcpy(ctrl->data_address, addr, sizeof(ctrl->data_address));\n\tctrl->data_port = e * 256 + f;\n\tDBG(\"Client PORT command accepted for %s:%d\", ctrl->data_address, ctrl->data_port);\n\tsend_msg(ctrl->sd, \"200 PORT command successful.\\r\\n\");\n}",
        "vulnerability": "Potential misuse of strlcpy",
        "reason": "While strlcpy is generally safe, incorrect assumptions about the size of ctrl->data_address or addr could still lead to logic errors. If sizeof(ctrl->data_address) is smaller than the actual size of addr, this could cause truncation, leading to incorrect behavior or security issues.",
        "file_name": "198399.sol"
    },
    {
        "function_name": "handle_PORT",
        "code": "static void handle_PORT(ctrl_t *ctrl, char *str)\n{\n\tint a, b, c, d, e, f;\n\tchar addr[INET_ADDRSTRLEN];\n\tstruct sockaddr_in sin;\n\tif (ctrl->data_sd > 0) {\n\t\tuev_io_stop(&ctrl->data_watcher);\n\t\tclose(ctrl->data_sd);\n\t\tctrl->data_sd = -1;\n\t}\n\tsscanf(str, \"%d,%d,%d,%d,%d,%d\", &a, &b, &c, &d, &e, &f);\n\tsprintf(addr, \"%d.%d.%d.%d\", a, b, c, d);\n\tif (!inet_aton(addr, &(sin.sin_addr))) {\n\t\tERR(0, \"Invalid address '%s' given to PORT command\", addr);\n\t\tsend_msg(ctrl->sd, \"500 Illegal PORT command.\\r\\n\");\n\t\treturn;\n\t}\n\tstrlcpy(ctrl->data_address, addr, sizeof(ctrl->data_address));\n\tctrl->data_port = e * 256 + f;\n\tDBG(\"Client PORT command accepted for %s:%d\", ctrl->data_address, ctrl->data_port);\n\tsend_msg(ctrl->sd, \"200 PORT command successful.\\r\\n\");\n}",
        "vulnerability": "Input Injection",
        "reason": "The use of sscanf without strict input validation allows attackers to inject unexpected or malformed input, potentially leading to buffer overflow or unexpected behavior due to incorrect parsing of the input string.",
        "file_name": "198399.sol"
    },
    {
        "function_name": "handle_PORT",
        "code": "static void handle_PORT(ctrl_t *ctrl, char *str)\n{\n\tint a, b, c, d, e, f;\n\tchar addr[INET_ADDRSTRLEN];\n\tstruct sockaddr_in sin;\n\tif (ctrl->data_sd > 0) {\n\t\tuev_io_stop(&ctrl->data_watcher);\n\t\tclose(ctrl->data_sd);\n\t\tctrl->data_sd = -1;\n\t}\n\tsscanf(str, \"%d,%d,%d,%d,%d,%d\", &a, &b, &c, &d, &e, &f);\n\tsprintf(addr, \"%d.%d.%d.%d\", a, b, c, d);\n\tif (!inet_aton(addr, &(sin.sin_addr))) {\n\t\tERR(0, \"Invalid address '%s' given to PORT command\", addr);\n\t\tsend_msg(ctrl->sd, \"500 Illegal PORT command.\\r\\n\");\n\t\treturn;\n\t}\n\tstrlcpy(ctrl->data_address, addr, sizeof(ctrl->data_address));\n\tctrl->data_port = e * 256 + f;\n\tDBG(\"Client PORT command accepted for %s:%d\", ctrl->data_address, ctrl->data_port);\n\tsend_msg(ctrl->sd, \"200 PORT command successful.\\r\\n\");\n}",
        "vulnerability": "Buffer Overflow",
        "reason": "The use of sprintf without checking the length of the resulting string can lead to a buffer overflow if the values of a, b, c, or d exceed the expected range, potentially allowing an attacker to overwrite adjacent memory.",
        "file_name": "198399.sol"
    },
    {
        "function_name": "handle_PORT",
        "code": "static void handle_PORT(ctrl_t *ctrl, char *str)\n{\n\tint a, b, c, d, e, f;\n\tchar addr[INET_ADDRSTRLEN];\n\tstruct sockaddr_in sin;\n\tif (ctrl->data_sd > 0) {\n\t\tuev_io_stop(&ctrl->data_watcher);\n\t\tclose(ctrl->data_sd);\n\t\tctrl->data_sd = -1;\n\t}\n\tsscanf(str, \"%d,%d,%d,%d,%d,%d\", &a, &b, &c, &d, &e, &f);\n\tsprintf(addr, \"%d.%d.%d.%d\", a, b, c, d);\n\tif (!inet_aton(addr, &(sin.sin_addr))) {\n\t\tERR(0, \"Invalid address '%s' given to PORT command\", addr);\n\t\tsend_msg(ctrl->sd, \"500 Illegal PORT command.\\r\\n\");\n\t\treturn;\n\t}\n\tstrlcpy(ctrl->data_address, addr, sizeof(ctrl->data_address));\n\tctrl->data_port = e * 256 + f;\n\tDBG(\"Client PORT command accepted for %s:%d\", ctrl->data_address, ctrl->data_port);\n\tsend_msg(ctrl->sd, \"200 PORT command successful.\\r\\n\");\n}",
        "vulnerability": "Improper Boundary Check",
        "reason": "Although strlcpy is used, there's no verification of the size of the destination buffer (ctrl->data_address) relative to the source string (addr). If the destination buffer is smaller than expected, it could lead to truncated data being used elsewhere in the code, potentially leading to logic errors or security issues.",
        "file_name": "198399.sol"
    }
]