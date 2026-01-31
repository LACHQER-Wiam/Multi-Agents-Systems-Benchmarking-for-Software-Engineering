[
    {
        "function_name": "parse_rtcp_bye",
        "code": "static void parse_rtcp_bye(pjmedia_rtcp_session *sess,\n\t\t\t   const void *pkt,\n\t\t\t   pj_size_t size)\n{\n    pj_str_t reason = {\"-\", 1};\n    if (size > 8) {\n\treason.slen = PJ_MIN(sizeof(sess->stat.peer_sdes_buf_),\n                             *((pj_uint8_t*)pkt+8));\n        reason.slen = PJ_MIN(reason.slen, size-9);\n\tpj_memcpy(sess->stat.peer_sdes_buf_, ((pj_uint8_t*)pkt+9),\n\t\t  reason.slen);\n\treason.ptr = sess->stat.peer_sdes_buf_;\n    }\n    PJ_LOG(5, (sess->name, \"Received RTCP BYE, reason: %.*s\",\n\t       reason.slen, reason.ptr));\n}",
        "vulnerability": "Buffer Overflow",
        "reason": "The code does not properly validate the length of the incoming RTCP BYE packet reason string before copying it into sess->stat.peer_sdes_buf_. An attacker can craft a packet with a size that exceeds the buffer capacity, leading to a buffer overflow when pj_memcpy is called. This could result in arbitrary code execution or crashing the application.",
        "file_name": "355014.sol"
    },
    {
        "function_name": "parse_rtcp_bye",
        "code": "static void parse_rtcp_bye(pjmedia_rtcp_session *sess,\n\t\t\t   const void *pkt,\n\t\t\t   pj_size_t size)\n{\n    pj_str_t reason = {\"-\", 1};\n    if (size > 8) {\n\treason.slen = PJ_MIN(sizeof(sess->stat.peer_sdes_buf_),\n                             *((pj_uint8_t*)pkt+8));\n        reason.slen = PJ_MIN(reason.slen, size-9);\n\tpj_memcpy(sess->stat.peer_sdes_buf_, ((pj_uint8_t*)pkt+9),\n\t\t  reason.slen);\n\treason.ptr = sess->stat.peer_sdes_buf_;\n    }\n    PJ_LOG(5, (sess->name, \"Received RTCP BYE, reason: %.*s\",\n\t       reason.slen, reason.ptr));\n}",
        "vulnerability": "Integer Overflow",
        "reason": "The calculation of reason.slen using PJ_MIN might lead to an integer overflow if the value at *((pj_uint8_t*)pkt+8) is large enough. This could result in unexpected behavior and potentially allow an attacker to bypass length checks or cause incorrect memory operations.",
        "file_name": "355014.sol"
    },
    {
        "function_name": "parse_rtcp_bye",
        "code": "static void parse_rtcp_bye(pjmedia_rtcp_session *sess,\n\t\t\t   const void *pkt,\n\t\t\t   pj_size_t size)\n{\n    pj_str_t reason = {\"-\", 1};\n    if (size > 8) {\n\treason.slen = PJ_MIN(sizeof(sess->stat.peer_sdes_buf_),\n                             *((pj_uint8_t*)pkt+8));\n        reason.slen = PJ_MIN(reason.slen, size-9);\n\tpj_memcpy(sess->stat.peer_sdes_buf_, ((pj_uint8_t*)pkt+9),\n\t\t  reason.slen);\n\treason.ptr = sess->stat.peer_sdes_buf_;\n    }\n    PJ_LOG(5, (sess->name, \"Received RTCP BYE, reason: %.*s\",\n\t       reason.slen, reason.ptr));\n}",
        "vulnerability": "Information Disclosure",
        "reason": "The function logs the reason string without sanitization, which might contain sensitive information if an attacker crafts the packet payload. This could lead to information disclosure in the logs, allowing an attacker to gain insights into the application\u2019s processing or leverage it for further attacks.",
        "file_name": "355014.sol"
    },
    {
        "function_name": "parse_rtcp_bye",
        "code": "static void parse_rtcp_bye(pjmedia_rtcp_session *sess,\n\t\t\t   const void *pkt,\n\t\t\t   pj_size_t size)\n{\n    pj_str_t reason = {\"-\", 1};\n    if (size > 8) {\n\treason.slen = PJ_MIN(sizeof(sess->stat.peer_sdes_buf_),\n                             *((pj_uint8_t*)pkt+8));\n        reason.slen = PJ_MIN(reason.slen, size-9);\n\tpj_memcpy(sess->stat.peer_sdes_buf_, ((pj_uint8_t*)pkt+9),\n\t\t  reason.slen);\n\treason.ptr = sess->stat.peer_sdes_buf_;\n    }\n    PJ_LOG(5, (sess->name, \"Received RTCP BYE, reason: %.*s\",\n\t       reason.slen, reason.ptr));\n}",
        "vulnerability": "Buffer Overflow",
        "reason": "The code does not properly ensure that the length of data being copied into sess->stat.peer_sdes_buf_ does not exceed its buffer size. An attacker can exploit this by crafting an RTCP packet with a large reason length, leading to a buffer overflow.",
        "file_name": "355014.sol"
    },
    {
        "function_name": "parse_rtcp_bye",
        "code": "static void parse_rtcp_bye(pjmedia_rtcp_session *sess,\n\t\t\t   const void *pkt,\n\t\t\t   pj_size_t size)\n{\n    pj_str_t reason = {\"-\", 1};\n    if (size > 8) {\n\treason.slen = PJ_MIN(sizeof(sess->stat.peer_sdes_buf_),\n                             *((pj_uint8_t*)pkt+8));\n        reason.slen = PJ_MIN(reason.slen, size-9);\n\tpj_memcpy(sess->stat.peer_sdes_buf_, ((pj_uint8_t*)pkt+9),\n\t\t  reason.slen);\n\treason.ptr = sess->stat.peer_sdes_buf_;\n    }\n    PJ_LOG(5, (sess->name, \"Received RTCP BYE, reason: %.*s\",\n\t       reason.slen, reason.ptr));\n}",
        "vulnerability": "Improper Length Handling",
        "reason": "The code calculates reason length using the 9th byte of the packet, assuming it fits within the buffer. However, without validation, this can cause incorrect length handling, potentially allowing data leaks or memory corruption.",
        "file_name": "355014.sol"
    },
    {
        "function_name": "parse_rtcp_bye",
        "code": "static void parse_rtcp_bye(pjmedia_rtcp_session *sess,\n\t\t\t   const void *pkt,\n\t\t\t   pj_size_t size)\n{\n    pj_str_t reason = {\"-\", 1};\n    if (size > 8) {\n\treason.slen = PJ_MIN(sizeof(sess->stat.peer_sdes_buf_),\n                             *((pj_uint8_t*)pkt+8));\n        reason.slen = PJ_MIN(reason.slen, size-9);\n\tpj_memcpy(sess->stat.peer_sdes_buf_, ((pj_uint8_t*)pkt+9),\n\t\t  reason.slen);\n\treason.ptr = sess->stat.peer_sdes_buf_;\n    }\n    PJ_LOG(5, (sess->name, \"Received RTCP BYE, reason: %.*s\",\n\t       reason.slen, reason.ptr));\n}",
        "vulnerability": "Potential Information Leak",
        "reason": "The function logs the reason string without ensuring it is null-terminated. If sess->stat.peer_sdes_buf_ is not properly managed, this could cause logging of unintended memory data, leading to an information leak.",
        "file_name": "355014.sol"
    }
]