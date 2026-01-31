[
    {
        "function_name": "gpg_ctx_add_recipient",
        "code": "gpg_ctx_add_recipient (struct _GpgCtx *gpg,\n                       const gchar *keyid)\n{\n\tgchar *safe_keyid;\n\tif (gpg->mode != GPG_CTX_MODE_ENCRYPT && gpg->mode != GPG_CTX_MODE_EXPORT)\n\t\treturn;\n\tif (!gpg->recipients)\n\t\tgpg->recipients = g_ptr_array_new ();\n\tg_return_if_fail (keyid != NULL);\n\tif (strchr (keyid, '@') != NULL) {\n\t\tsafe_keyid = g_strdup_printf (\"<%s>\", keyid);\n\t} else {\n\t\tsafe_keyid = g_strdup (keyid);\n\t}\n\tg_ptr_array_add (gpg->recipients, safe_keyid);\n}",
        "vulnerability": "Null pointer dereference",
        "reason": "The code does not check if the keyid parameter is NULL before using it. This can lead to a null pointer dereference vulnerability, where an attacker can pass a NULL keyid parameter to the function, causing the program to crash or potentially execute arbitrary code.",
        "file_name": "376350.sol"
    },
    {
        "function_name": "gpg_ctx_add_recipient",
        "code": "gpg_ctx_add_recipient (struct _GpgCtx *gpg,\n                       const gchar *keyid)\n{\n\tgchar *safe_keyid;\n\tif (gpg->mode != GPG_CTX_MODE_ENCRYPT && gpg->mode != GPG_CTX_MODE_EXPORT)\n\t\treturn;\n\tif (!gpg->recipients)\n\t\tgpg->recipients = g_ptr_array_new ();\n\tg_return_if_fail (keyid != NULL);\n\tif (strchr (keyid, '@') != NULL) {\n\t\tsafe_keyid = g_strdup_printf (\"<%s>\", keyid);\n\t} else {\n\t\tsafe_keyid = g_strdup (keyid);\n\t}\n\tg_ptr_array_add (gpg->recipients, safe_keyid);\n}",
        "vulnerability": "Format string vulnerability",
        "reason": "The code uses the keyid parameter directly in a format string without proper sanitization, allowing an attacker to potentially exploit a format string vulnerability. An attacker can craft a malicious keyid containing format specifiers (%s, %n, etc.) to read or write arbitrary memory, manipulate program flow, or execute arbitrary code.",
        "file_name": "376350.sol"
    },
    {
        "function_name": "gpg_ctx_add_recipient",
        "code": "gpg_ctx_add_recipient (struct _GpgCtx *gpg,\n                       const gchar *keyid)\n{\n\tgchar *safe_keyid;\n\tif (gpg->mode != GPG_CTX_MODE_ENCRYPT && gpg->mode != GPG_CTX_MODE_EXPORT)\n\t\treturn;\n\tif (!gpg->recipients)\n\t\tgpg->recipients = g_ptr_array_new ();\n\tg_return_if_fail (keyid != NULL);\n\tif (strchr (keyid, '@') != NULL) {\n\t\tsafe_keyid = g_strdup_printf (\"<%s>\", keyid);\n\t} else {\n\t\tsafe_keyid = g_strdup (keyid);\n\t}\n\tg_ptr_array_add (gpg->recipients, safe_keyid);\n}",
        "vulnerability": "Memory leak",
        "reason": "The code dynamically allocates memory for the safe_keyid variable using g_strdup_printf or g_strdup functions, but it does not free this memory after adding it to the gpg->recipients array. This can lead to a memory leak vulnerability, where memory allocated for safe_keyid is not properly released, causing the program to consume excessive memory over time and potentially crash.",
        "file_name": "376350.sol"
    },
    {
        "function_name": "gpg_ctx_add_recipient",
        "code": "gpg_ctx_add_recipient (struct _GpgCtx *gpg,\n                       const gchar *keyid)\n{\n\tgchar *safe_keyid;\n\tif (gpg->mode != GPG_CTX_MODE_ENCRYPT && gpg->mode != GPG_CTX_MODE_EXPORT)\n\t\treturn;\n\tif (!gpg->recipients)\n\t\tgpg->recipients = g_ptr_array_new ();\n\tg_return_if_fail (keyid != NULL);\n\tif (strchr (keyid, '@') != NULL) {\n\t\tsafe_keyid = g_strdup_printf (\"<%s>\", keyid);\n\t} else {\n\t\tsafe_keyid = g_strdup (keyid);\n\t}\n\tg_ptr_array_add (gpg->recipients, safe_keyid);\n}",
        "vulnerability": "Null pointer dereference",
        "reason": "The code does not check if the keyid parameter is NULL before using it. This can lead to a null pointer dereference vulnerability, where an attacker can provide a NULL keyid parameter to crash the application or potentially execute arbitrary code.",
        "file_name": "376350.sol"
    },
    {
        "function_name": "gpg_ctx_add_recipient",
        "code": "gpg_ctx_add_recipient (struct _GpgCtx *gpg,\n                       const gchar *keyid)\n{\n\tgchar *safe_keyid;\n\tif (gpg->mode != GPG_CTX_MODE_ENCRYPT && gpg->mode != GPG_CTX_MODE_EXPORT)\n\t\treturn;\n\tif (!gpg->recipients)\n\t\tgpg->recipients = g_ptr_array_new ();\n\tg_return_if_fail (keyid != NULL);\n\tif (strchr (keyid, '@') != NULL) {\n\t\tsafe_keyid = g_strdup_printf (\"<%s>\", keyid);\n\t} else {\n\t\tsafe_keyid = g_strdup (keyid);\n\t}\n\tg_ptr_array_add (gpg->recipients, safe_keyid);\n}",
        "vulnerability": "Format string vulnerability",
        "reason": "The g_strdup_printf function is used to format the keyid parameter with the '<' and '>' characters. If the keyid parameter contains format specifiers (%s, %d, etc.), an attacker could potentially exploit this to perform a format string attack, leading to information disclosure, denial of service, or even remote code execution.",
        "file_name": "376350.sol"
    },
    {
        "function_name": "gpg_ctx_add_recipient",
        "code": "gpg_ctx_add_recipient (struct _GpgCtx *gpg,\n                       const gchar *keyid)\n{\n\tgchar *safe_keyid;\n\tif (gpg->mode != GPG_CTX_MODE_ENCRYPT && gpg->mode != GPG_CTX_MODE_EXPORT)\n\t\treturn;\n\tif (!gpg->recipients)\n\t\tgpg->recipients = g_ptr_array_new ();\n\tg_return_if_fail (keyid != NULL);\n\tif (strchr (keyid, '@') != NULL) {\n\t\tsafe_keyid = g_strdup_printf (\"<%s>\", keyid);\n\t} else {\n\t\tsafe_keyid = g_strdup (keyid);\n\t}\n\tg_ptr_array_add (gpg->recipients, safe_keyid);\n}",
        "vulnerability": "Memory corruption",
        "reason": "The safe_keyid variable is added to the gpg->recipients array without checking the size of the array or validating the input. An attacker could provide a specially crafted keyid parameter to overflow the recipients array, leading to memory corruption issues such as buffer overflows or arbitrary code execution.",
        "file_name": "376350.sol"
    }
]