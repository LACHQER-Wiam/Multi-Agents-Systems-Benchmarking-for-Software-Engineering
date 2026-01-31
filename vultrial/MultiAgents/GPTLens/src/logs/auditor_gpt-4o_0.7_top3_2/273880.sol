[
    {
        "function_name": "handle_PORT",
        "code": "static void handle_PORT(ctrl_t *ctrl, char *str)\n{\n\tint a, b, c, d, e, f;\n\tchar addr[INET_ADDRSTRLEN];\n\tstruct sockaddr_in sin;\n\tif (ctrl->data_sd > 0) {\n\t\tuev_io_stop(&ctrl->data_watcher);\n\t\tclose(ctrl->data_sd);\n\t\tctrl->data_sd = -1;\n\t}\n\tsscanf(str, \"%d,%d,%d,%d,%d,%d\", &a, &b, &c, &d, &e, &f);\n\tsnprintf(addr, sizeof(addr), \"%d.%d.%d.%d\", a, b, c, d);\n\tif (!inet_aton(addr, &(sin.sin_addr))) {\n\t\tERR(0, \"Invalid address '%s' given to PORT command\", addr);\n\t\tsend_msg(ctrl->sd, \"500 Illegal PORT command.\\r\\n\");\n\t\treturn;\n\t}\n\tstrlcpy(ctrl->data_address, addr, sizeof(ctrl->data_address));\n\tctrl->data_port = e * 256 + f;\n\tDBG(\"Client PORT command accepted for %s:%d\", ctrl->data_address, ctrl->data_port);\n\tsend_msg(ctrl->sd, \"200 PORT command successful.\\r\\n\");\n}",
        "vulnerability": "Input Validation Issue",
        "reason": "The code uses sscanf to parse the input string and does not validate the number of arguments successfully scanned. This can lead to undefined behavior if fewer than six integers are provided. An attacker could exploit this by sending a malformed PORT command, potentially causing the application to behave unpredictably or crash.",
        "file_name": "273880.sol"
    },
    {
        "function_name": "handle_PORT",
        "code": "static void handle_PORT(ctrl_t *ctrl, char *str)\n{\n\tint a, b, c, d, e, f;\n\tchar addr[INET_ADDRSTRLEN];\n\tstruct sockaddr_in sin;\n\tif (ctrl->data_sd > 0) {\n\t\tuev_io_stop(&ctrl->data_watcher);\n\t\tclose(ctrl->data_sd);\n\t\tctrl->data_sd = -1;\n\t}\n\tsscanf(str, \"%d,%d,%d,%d,%d,%d\", &a, &b, &c, &d, &e, &f);\n\tsnprintf(addr, sizeof(addr), \"%d.%d.%d.%d\", a, b, c, d);\n\tif (!inet_aton(addr, &(sin.sin_addr))) {\n\t\tERR(0, \"Invalid address '%s' given to PORT command\", addr);\n\t\tsend_msg(ctrl->sd, \"500 Illegal PORT command.\\r\\n\");\n\t\treturn;\n\t}\n\tstrlcpy(ctrl->data_address, addr, sizeof(ctrl->data_address));\n\tctrl->data_port = e * 256 + f;\n\tDBG(\"Client PORT command accepted for %s:%d\", ctrl->data_address, ctrl->data_port);\n\tsend_msg(ctrl->sd, \"200 PORT command successful.\\r\\n\");\n}",
        "vulnerability": "Improper Integer Handling",
        "reason": "The code does not validate the range of the integers a, b, c, and d before using them to form an IP address. If any of these integers are out of the valid range for an octet (0-255), it could result in incorrect behavior or unexpected addresses being used, potentially allowing an attacker to bypass address-based controls.",
        "file_name": "273880.sol"
    },
    {
        "function_name": "handle_PORT",
        "code": "static void handle_PORT(ctrl_t *ctrl, char *str)\n{\n\tint a, b, c, d, e, f;\n\tchar addr[INET_ADDRSTRLEN];\n\tstruct sockaddr_in sin;\n\tif (ctrl->data_sd > 0) {\n\t\tuev_io_stop(&ctrl->data_watcher);\n\t\tclose(ctrl->data_sd);\n\t\tctrl->data_sd = -1;\n\t}\n\tsscanf(str, \"%d,%d,%d,%d,%d,%d\", &a, &b, &c, &d, &e, &f);\n\tsnprintf(addr, sizeof(addr), \"%d.%d.%d.%d\", a, b, c, d);\n\tif (!inet_aton(addr, &(sin.sin_addr))) {\n\t\tERR(0, \"Invalid address '%s' given to PORT command\", addr);\n\t\tsend_msg(ctrl->sd, \"500 Illegal PORT command.\\r\\n\");\n\t\treturn;\n\t}\n\tstrlcpy(ctrl->data_address, addr, sizeof(ctrl->data_address));\n\tctrl->data_port = e * 256 + f;\n\tDBG(\"Client PORT command accepted for %s:%d\", ctrl->data_address, ctrl->data_port);\n\tsend_msg(ctrl->sd, \"200 PORT command successful.\\r\\n\");\n}",
        "vulnerability": "Potential Buffer Overflow",
        "reason": "While strlcpy is safer than strcpy, it is still crucial to ensure that the destination buffer is adequately sized for the source data. There is no validation or clear structure definition provided in the code snippet to confirm that ctrl->data_address is appropriately sized to hold the string representation of an IP address. If it is undersized, this could lead to a buffer overflow, which an attacker can exploit to execute arbitrary code.",
        "file_name": "273880.sol"
    },
    {
        "function_name": "handle_PORT",
        "code": "static void handle_PORT(ctrl_t *ctrl, char *str)\n{\n\tint a, b, c, d, e, f;\n\tchar addr[INET_ADDRSTRLEN];\n\tstruct sockaddr_in sin;\n\tif (ctrl->data_sd > 0) {\n\t\tuev_io_stop(&ctrl->data_watcher);\n\t\tclose(ctrl->data_sd);\n\t\tctrl->data_sd = -1;\n\t}\n\tsscanf(str, \"%d,%d,%d,%d,%d,%d\", &a, &b, &c, &d, &e, &f);\n\tsnprintf(addr, sizeof(addr), \"%d.%d.%d.%d\", a, b, c, d);\n\tif (!inet_aton(addr, &(sin.sin_addr))) {\n\t\tERR(0, \"Invalid address '%s' given to PORT command\", addr);\n\t\tsend_msg(ctrl->sd, \"500 Illegal PORT command.\\r\\n\");\n\t\treturn;\n\t}\n\tstrlcpy(ctrl->data_address, addr, sizeof(ctrl->data_address));\n\tctrl->data_port = e * 256 + f;\n\tDBG(\"Client PORT command accepted for %s:%d\", ctrl->data_address, ctrl->data_port);\n\tsend_msg(ctrl->sd, \"200 PORT command successful.\\r\\n\");\n}",
        "vulnerability": "Improper Input Validation",
        "reason": "The sscanf function is used to parse the input string without validating the input format. This can lead to buffer overflows if the input does not strictly follow the expected format or if it includes values that are too large to store in the provided integer variables. An attacker could exploit this by sending specially crafted input to the function, potentially causing memory corruption or allowing arbitrary code execution.",
        "file_name": "273880.sol"
    },
    {
        "function_name": "handle_PORT",
        "code": "static void handle_PORT(ctrl_t *ctrl, char *str)\n{\n\tint a, b, c, d, e, f;\n\tchar addr[INET_ADDRSTRLEN];\n\tstruct sockaddr_in sin;\n\tif (ctrl->data_sd > 0) {\n\t\tuev_io_stop(&ctrl->data_watcher);\n\t\tclose(ctrl->data_sd);\n\t\tctrl->data_sd = -1;\n\t}\n\tsscanf(str, \"%d,%d,%d,%d,%d,%d\", &a, &b, &c, &d, &e, &f);\n\tsnprintf(addr, sizeof(addr), \"%d.%d.%d.%d\", a, b, c, d);\n\tif (!inet_aton(addr, &(sin.sin_addr))) {\n\t\tERR(0, \"Invalid address '%s' given to PORT command\", addr);\n\t\tsend_msg(ctrl->sd, \"500 Illegal PORT command.\\r\\n\");\n\t\treturn;\n\t}\n\tstrlcpy(ctrl->data_address, addr, sizeof(ctrl->data_address));\n\tctrl->data_port = e * 256 + f;\n\tDBG(\"Client PORT command accepted for %s:%d\", ctrl->data_address, ctrl->data_port);\n\tsend_msg(ctrl->sd, \"200 PORT command successful.\\r\\n\");\n}",
        "vulnerability": "Integer Overflow in Address Construction",
        "reason": "The construction of the IP address using integers a, b, c, and d is vulnerable to integer overflow. If the integers are not properly validated, they could exceed the allowable range for an IP address segment (0-255), resulting in an incorrect or malicious IP address being created. This could potentially allow an attacker to manipulate the IP address used for subsequent connections.",
        "file_name": "273880.sol"
    },
    {
        "function_name": "handle_PORT",
        "code": "static void handle_PORT(ctrl_t *ctrl, char *str)\n{\n\tint a, b, c, d, e, f;\n\tchar addr[INET_ADDRSTRLEN];\n\tstruct sockaddr_in sin;\n\tif (ctrl->data_sd > 0) {\n\t\tuev_io_stop(&ctrl->data_watcher);\n\t\tclose(ctrl->data_sd);\n\t\tctrl->data_sd = -1;\n\t}\n\tsscanf(str, \"%d,%d,%d,%d,%d,%d\", &a, &b, &c, &d, &e, &f);\n\tsnprintf(addr, sizeof(addr), \"%d.%d.%d.%d\", a, b, c, d);\n\tif (!inet_aton(addr, &(sin.sin_addr))) {\n\t\tERR(0, \"Invalid address '%s' given to PORT command\", addr);\n\t\tsend_msg(ctrl->sd, \"500 Illegal PORT command.\\r\\n\");\n\t\treturn;\n\t}\n\tstrlcpy(ctrl->data_address, addr, sizeof(ctrl->data_address));\n\tctrl->data_port = e * 256 + f;\n\tDBG(\"Client PORT command accepted for %s:%d\", ctrl->data_address, ctrl->data_port);\n\tsend_msg(ctrl->sd, \"200 PORT command successful.\\r\\n\");\n}",
        "vulnerability": "Integer Overflow in Port Calculation",
        "reason": "The calculation of the port number from the variables e and f can lead to an integer overflow if the values are not within their expected ranges (0-255). This could result in an incorrect port number being assigned, which could be used by an attacker to redirect connections to a malicious service or cause denial of service by using an invalid or privileged port number.",
        "file_name": "273880.sol"
    }
]