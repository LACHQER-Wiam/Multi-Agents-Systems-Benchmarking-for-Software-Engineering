[
    {
        "function_name": "parse_rtcp_bye",
        "code": "static void parse_rtcp_bye(pjmedia_rtcp_session *sess,\n\t\t\t   const void *pkt,\n\t\t\t   pj_size_t size)\n{\n    pj_str_t reason = {\"-\", 1};\n    if (size > 8) {\n\treason.slen = PJ_MIN(sizeof(sess->stat.peer_sdes_buf_),\n                             *((pj_uint8_t*)pkt+8));\n\tpj_memcpy(sess->stat.peer_sdes_buf_, ((pj_uint8_t*)pkt+9),\n\t\t  reason.slen);\n\treason.ptr = sess->stat.peer_sdes_buf_;\n    }\n    PJ_LOG(5, (sess->name, \"Received RTCP BYE, reason: %.*s\",\n\t       reason.slen, reason.ptr));\n}",
        "vulnerability": "Buffer Overflow",
        "reason": "The code copies data from the packet into sess->stat.peer_sdes_buf_ without verifying that the size of data to be copied (reason.slen) does not exceed the size of sess->stat.peer_sdes_buf_. If the incoming packet size is manipulated by an attacker to have a larger size, this could lead to a buffer overflow, potentially allowing for arbitrary code execution or other malicious behavior.",
        "file_name": "204195.sol"
    },
    {
        "function_name": "parse_rtcp_bye",
        "code": "static void parse_rtcp_bye(pjmedia_rtcp_session *sess,\n\t\t\t   const void *pkt,\n\t\t\t   pj_size_t size)\n{\n    pj_str_t reason = {\"-\", 1};\n    if (size > 8) {\n\treason.slen = PJ_MIN(sizeof(sess->stat.peer_sdes_buf_),\n                             *((pj_uint8_t*)pkt+8));\n\tpj_memcpy(sess->stat.peer_sdes_buf_, ((pj_uint8_t*)pkt+9),\n\t\t  reason.slen);\n\treason.ptr = sess->stat.peer_sdes_buf_;\n    }\n    PJ_LOG(5, (sess->name, \"Received RTCP BYE, reason: %.*s\",\n\t       reason.slen, reason.ptr));\n}",
        "vulnerability": "Inadequate Input Validation",
        "reason": "The function does not adequately validate the input packet size beyond checking if it is greater than 8. This lack of validation could allow an attacker to craft a packet that causes unexpected behavior or crashes by setting invalid values for the packet size, leading to improper handling of the data.",
        "file_name": "204195.sol"
    },
    {
        "function_name": "parse_rtcp_bye",
        "code": "static void parse_rtcp_bye(pjmedia_rtcp_session *sess,\n\t\t\t   const void *pkt,\n\t\t\t   pj_size_t size)\n{\n    pj_str_t reason = {\"-\", 1};\n    if (size > 8) {\n\treason.slen = PJ_MIN(sizeof(sess->stat.peer_sdes_buf_),\n                             *((pj_uint8_t*)pkt+8));\n\tpj_memcpy(sess->stat.peer_sdes_buf_, ((pj_uint8_t*)pkt+9),\n\t\t  reason.slen);\n\treason.ptr = sess->stat.peer_sdes_buf_;\n    }\n    PJ_LOG(5, (sess->name, \"Received RTCP BYE, reason: %.*s\",\n\t       reason.slen, reason.ptr));\n}",
        "vulnerability": "Information Disclosure",
        "reason": "The function logs the reason for the RTCP BYE message without sanitizing the input. This could lead to a scenario where sensitive information included in the RTCP packet is logged and potentially exposed to unauthorized users, risking information disclosure.",
        "file_name": "204195.sol"
    },
    {
        "function_name": "parse_rtcp_bye",
        "code": "static void parse_rtcp_bye(pjmedia_rtcp_session *sess,\n\t\t\t   const void *pkt,\n\t\t\t   pj_size_t size)\n{\n    pj_str_t reason = {\"-\", 1};\n    if (size > 8) {\n\treason.slen = PJ_MIN(sizeof(sess->stat.peer_sdes_buf_),\n                             *((pj_uint8_t*)pkt+8));\n\tpj_memcpy(sess->stat.peer_sdes_buf_, ((pj_uint8_t*)pkt+9),\n\t\t  reason.slen);\n\treason.ptr = sess->stat.peer_sdes_buf_;\n    }\n    PJ_LOG(5, (sess->name, \"Received RTCP BYE, reason: %.*s\",\n\t       reason.slen, reason.ptr));\n}",
        "vulnerability": "Buffer Overflow",
        "reason": "The function does not properly verify the length of the incoming packet's data before copying it to sess->stat.peer_sdes_buf_. The length is determined by the 9th byte of the packet, which can be controlled by an attacker. If this length is larger than the buffer size, it will result in a buffer overflow, potentially allowing an attacker to overwrite adjacent memory.",
        "file_name": "204195.sol"
    },
    {
        "function_name": "parse_rtcp_bye",
        "code": "static void parse_rtcp_bye(pjmedia_rtcp_session *sess,\n\t\t\t   const void *pkt,\n\t\t\t   pj_size_t size)\n{\n    pj_str_t reason = {\"-\", 1};\n    if (size > 8) {\n\treason.slen = PJ_MIN(sizeof(sess->stat.peer_sdes_buf_),\n                             *((pj_uint8_t*)pkt+8));\n\tpj_memcpy(sess->stat.peer_sdes_buf_, ((pj_uint8_t*)pkt+9),\n\t\t  reason.slen);\n\treason.ptr = sess->stat.peer_sdes_buf_;\n    }\n    PJ_LOG(5, (sess->name, \"Received RTCP BYE, reason: %.*s\",\n\t       reason.slen, reason.ptr));\n}",
        "vulnerability": "Improper Input Validation",
        "reason": "The function does not validate the content of the incoming packet, specifically the byte used to determine the length of the 'reason' string. This can lead to unexpected behavior or crashes if the byte indicates a length that causes the function to read beyond the bounds of the packet.",
        "file_name": "204195.sol"
    },
    {
        "function_name": "parse_rtcp_bye",
        "code": "static void parse_rtcp_bye(pjmedia_rtcp_session *sess,\n\t\t\t   const void *pkt,\n\t\t\t   pj_size_t size)\n{\n    pj_str_t reason = {\"-\", 1};\n    if (size > 8) {\n\treason.slen = PJ_MIN(sizeof(sess->stat.peer_sdes_buf_),\n                             *((pj_uint8_t*)pkt+8));\n\tpj_memcpy(sess->stat.peer_sdes_buf_, ((pj_uint8_t*)pkt+9),\n\t\t  reason.slen);\n\treason.ptr = sess->stat.peer_sdes_buf_;\n    }\n    PJ_LOG(5, (sess->name, \"Received RTCP BYE, reason: %.*s\",\n\t       reason.slen, reason.ptr));\n}",
        "vulnerability": "Potential Information Disclosure",
        "reason": "If the packet size is less than the length specified in the 9th byte, the function might log uninitialized data from sess->stat.peer_sdes_buf_, potentially disclosing sensitive information from the memory.",
        "file_name": "204195.sol"
    }
]