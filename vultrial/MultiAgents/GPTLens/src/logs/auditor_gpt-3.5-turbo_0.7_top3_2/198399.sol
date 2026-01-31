[
    {
        "function_name": "handle_PORT",
        "code": "static void handle_PORT(ctrl_t *ctrl, char *str)\n{\n\tint a, b, c, d, e, f;\n\tchar addr[INET_ADDRSTRLEN];\n\tstruct sockaddr_in sin;\n\tif (ctrl->data_sd > 0) {\n\t\tuev_io_stop(&ctrl->data_watcher);\n\t\tclose(ctrl->data_sd);\n\t\tctrl->data_sd = -1;\n\t}\n\tsscanf(str, \"%d,%d,%d,%d,%d,%d\", &a, &b, &c, &d, &e, &f);\n\tsprintf(addr, \"%d.%d.%d.%d\", a, b, c, d);\n\tif (!inet_aton(addr, &(sin.sin_addr))) {\n\t\tERR(0, \"Invalid address '%s' given to PORT command\", addr);\n\t\tsend_msg(ctrl->sd, \"500 Illegal PORT command.\\r\\n\");\n\t\treturn;\n\t}\n\tstrlcpy(ctrl->data_address, addr, sizeof(ctrl->data_address));\n\tctrl->data_port = e * 256 + f;\n\tDBG(\"Client PORT command accepted for %s:%d\", ctrl->data_address, ctrl->data_port);\n\tsend_msg(ctrl->sd, \"200 PORT command successful.\\r\\n\");\n}",
        "vulnerability": "Buffer Overflow",
        "reason": "The function does not perform bounds checking when copying the address into the 'addr' buffer using sprintf. This could lead to a buffer overflow if the input string 'str' is longer than the allocated space for 'addr', resulting in potential memory corruption and exploitation by an attacker.",
        "file_name": "198399.sol"
    },
    {
        "function_name": "handle_PORT",
        "code": "static void handle_PORT(ctrl_t *ctrl, char *str)\n{\n\tint a, b, c, d, e, f;\n\tchar addr[INET_ADDRSTRLEN];\n\tstruct sockaddr_in sin;\n\tif (ctrl->data_sd > 0) {\n\t\tuev_io_stop(&ctrl->data_watcher);\n\t\tclose(ctrl->data_sd);\n\t\tctrl->data_sd = -1;\n\t}\n\tsscanf(str, \"%d,%d,%d,%d,%d,%d\", &a, &b, &c, &d, &e, &f);\n\tsprintf(addr, \"%d.%d.%d.%d\", a, b, c, d);\n\tif (!inet_aton(addr, &(sin.sin_addr))) {\n\t\tERR(0, \"Invalid address '%s' given to PORT command\", addr);\n\t\tsend_msg(ctrl->sd, \"500 Illegal PORT command.\\r\\n\");\n\t\treturn;\n\t}\n\tstrlcpy(ctrl->data_address, addr, sizeof(ctrl->data_address));\n\tctrl->data_port = e * 256 + f;\n\tDBG(\"Client PORT command accepted for %s:%d\", ctrl->data_address, ctrl->data_port);\n\tsend_msg(ctrl->sd, \"200 PORT command successful.\\r\\n\");\n}",
        "vulnerability": "Integer Overflow",
        "reason": "The calculation of 'ctrl->data_port = e * 256 + f;' does not include proper validation for potential integer overflow. If the values of 'e' and 'f' are large enough, the result of the multiplication could exceed the maximum value that can be stored in an integer, leading to integer overflow. This can be exploited by an attacker to manipulate the port number and potentially cause denial of service or other malicious activities.",
        "file_name": "198399.sol"
    },
    {
        "function_name": "handle_PORT",
        "code": "static void handle_PORT(ctrl_t *ctrl, char *str)\n{\n\tint a, b, c, d, e, f;\n\tchar addr[INET_ADDRSTRLEN];\n\tstruct sockaddr_in sin;\n\tif (ctrl->data_sd > 0) {\n\t\tuev_io_stop(&ctrl->data_watcher);\n\t\tclose(ctrl->data_sd);\n\t\tctrl->data_sd = -1;\n\t}\n\tsscanf(str, \"%d,%d,%d,%d,%d,%d\", &a, &b, &c, &d, &e, &f);\n\tsprintf(addr, \"%d.%d.%d.%d\", a, b, c, d);\n\tif (!inet_aton(addr, &(sin.sin_addr))) {\n\t\tERR(0, \"Invalid address '%s' given to PORT command\", addr);\n\t\tsend_msg(ctrl->sd, \"500 Illegal PORT command.\\r\\n\");\n\t\treturn;\n\t}\n\tstrlcpy(ctrl->data_address, addr, sizeof(ctrl->data_address));\n\tctrl->data_port = e * 256 + f;\n\tDBG(\"Client PORT command accepted for %s:%d\", ctrl->data_address, ctrl->data_port);\n\tsend_msg(ctrl->sd, \"200 PORT command successful.\\r\\n\");\n}",
        "vulnerability": "Input Validation",
        "reason": "The function does not perform sufficient input validation on the 'str' parameter before parsing it with sscanf. This lack of validation could allow an attacker to craft malicious input that could lead to format string vulnerabilities, buffer overflows, or other exploitation techniques. Proper input validation should be implemented to prevent such security risks.",
        "file_name": "198399.sol"
    },
    {
        "function_name": "handle_PORT",
        "code": "static void handle_PORT(ctrl_t *ctrl, char *str)\n{\n\tint a, b, c, d, e, f;\n\tchar addr[INET_ADDRSTRLEN];\n\tstruct sockaddr_in sin;\n\tif (ctrl->data_sd > 0) {\n\t\tuev_io_stop(&ctrl->data_watcher);\n\t\tclose(ctrl->data_sd);\n\t\tctrl->data_sd = -1;\n\t}\n\tsscanf(str, \"%d,%d,%d,%d,%d,%d\", &a, &b, &c, &d, &e, &f);\n\tsprintf(addr, \"%d.%d.%d.%d\", a, b, c, d);\n\tif (!inet_aton(addr, &(sin.sin_addr))) {\n\t\tERR(0, \"Invalid address '%s' given to PORT command\", addr);\n\t\tsend_msg(ctrl->sd, \"500 Illegal PORT command.\\r\\n\");\n\t\treturn;\n\t}\n\tstrlcpy(ctrl->data_address, addr, sizeof(ctrl->data_address));\n\tctrl->data_port = e * 256 + f;\n\tDBG(\"Client PORT command accepted for %s:%d\", ctrl->data_address, ctrl->data_port);\n\tsend_msg(ctrl->sd, \"200 PORT command successful.\\r\\n\");\n}",
        "vulnerability": "Potential Buffer Overflow",
        "reason": "The function uses sprintf to format the IP address into the 'addr' buffer without checking the length of the input. An attacker could provide a malicious input that exceeds the size of the 'addr' buffer, leading to a buffer overflow and potentially overwriting adjacent memory.",
        "file_name": "198399.sol"
    },
    {
        "function_name": "handle_PORT",
        "code": "static void handle_PORT(ctrl_t *ctrl, char *str)\n{\n\tint a, b, c, d, e, f;\n\tchar addr[INET_ADDRSTRLEN];\n\tstruct sockaddr_in sin;\n\tif (ctrl->data_sd > 0) {\n\t\tuev_io_stop(&ctrl->data_watcher);\n\t\tclose(ctrl->data_sd);\n\t\tctrl->data_sd = -1;\n\t}\n\tsscanf(str, \"%d,%d,%d,%d,%d,%d\", &a, &b, &c, &d, &e, &f);\n\tsprintf(addr, \"%d.%d.%d.%d\", a, b, c, d);\n\tif (!inet_aton(addr, &(sin.sin_addr))) {\n\t\tERR(0, \"Invalid address '%s' given to PORT command\", addr);\n\t\tsend_msg(ctrl->sd, \"500 Illegal PORT command.\\r\\n\");\n\t\treturn;\n\t}\n\tstrlcpy(ctrl->data_address, addr, sizeof(ctrl->data_address));\n\tctrl->data_port = e * 256 + f;\n\tDBG(\"Client PORT command accepted for %s:%d\", ctrl->data_address, ctrl->data_port);\n\tsend_msg(ctrl->sd, \"200 PORT command successful.\\r\\n\");\n}",
        "vulnerability": "Potential Command Injection",
        "reason": "The function uses sscanf to parse the input 'str' without proper input validation. An attacker could inject malicious data in the 'str' parameter, leading to command injection vulnerabilities if not properly sanitized.",
        "file_name": "198399.sol"
    },
    {
        "function_name": "handle_PORT",
        "code": "static void handle_PORT(ctrl_t *ctrl, char *str)\n{\n\tint a, b, c, d, e, f;\n\tchar addr[INET_ADDRSTRLEN];\n\tstruct sockaddr_in sin;\n\tif (ctrl->data_sd > 0) {\n\t\tuev_io_stop(&ctrl->data_watcher);\n\t\tclose(ctrl->data_sd);\n\t\tctrl->data_sd = -1;\n\t}\n\tsscanf(str, \"%d,%d,%d,%d,%d,%d\", &a, &b, &c, &d, &e, &f);\n\tsprintf(addr, \"%d.%d.%d.%d\", a, b, c, d);\n\tif (!inet_aton(addr, &(sin.sin_addr))) {\n\t\tERR(0, \"Invalid address '%s' given to PORT command\", addr);\n\t\tsend_msg(ctrl->sd, \"500 Illegal PORT command.\\r\\n\");\n\t\treturn;\n\t}\n\tstrlcpy(ctrl->data_address, addr, sizeof(ctrl->data_address));\n\tctrl->data_port = e * 256 + f;\n\tDBG(\"Client PORT command accepted for %s:%d\", ctrl->data_address, ctrl->data_port);\n\tsend_msg(ctrl->sd, \"200 PORT command successful.\\r\\n\");\n}",
        "vulnerability": "Potential Denial of Service (DoS)",
        "reason": "The function does not perform proper input validation on the 'str' parameter, which could allow an attacker to provide malicious or unexpected data, leading to DoS attacks by causing the function to handle unexpected situations or crash due to invalid input.",
        "file_name": "198399.sol"
    }
]