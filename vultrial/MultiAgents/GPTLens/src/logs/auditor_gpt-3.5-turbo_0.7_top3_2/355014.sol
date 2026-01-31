[
    {
        "function_name": "parse_rtcp_bye",
        "code": "static void parse_rtcp_bye(pjmedia_rtcp_session *sess,\n\t\t\t   const void *pkt,\n\t\t\t   pj_size_t size)\n{\n    pj_str_t reason = {\"-\", 1};\n    if (size > 8) {\n\treason.slen = PJ_MIN(sizeof(sess->stat.peer_sdes_buf_),\n                             *((pj_uint8_t*)pkt+8));\n        reason.slen = PJ_MIN(reason.slen, size-9);\n\tpj_memcpy(sess->stat.peer_sdes_buf_, ((pj_uint8_t*)pkt+9),\n\t\t  reason.slen);\n\treason.ptr = sess->stat.peer_sdes_buf_;\n    }\n    PJ_LOG(5, (sess->name, \"Received RTCP BYE, reason: %.*s\",\n\t       reason.slen, reason.ptr));\n}",
        "vulnerability": "Buffer Overflow",
        "reason": "The code does not perform proper bounds checking when copying the reason string from the packet to the peer_sdes_buf_. This can lead to a buffer overflow if the size of the reason string in the packet is larger than the size of peer_sdes_buf_. An attacker could exploit this vulnerability by crafting a malicious RTCP BYE packet with a large reason string, causing a buffer overflow and potentially executing arbitrary code.",
        "file_name": "355014.sol"
    },
    {
        "function_name": "parse_rtcp_bye",
        "code": "static void parse_rtcp_bye(pjmedia_rtcp_session *sess,\n\t\t\t   const void *pkt,\n\t\t\t   pj_size_t size)\n{\n    pj_str_t reason = {\"-\", 1};\n    if (size > 8) {\n\treason.slen = PJ_MIN(sizeof(sess->stat.peer_sdes_buf_),\n                             *((pj_uint8_t*)pkt+8));\n        reason.slen = PJ_MIN(reason.slen, size-9);\n\tpj_memcpy(sess->stat.peer_sdes_buf_, ((pj_uint8_t*)pkt+9),\n\t\t  reason.slen);\n\treason.ptr = sess->stat.peer_sdes_buf_;\n    }\n    PJ_LOG(5, (sess->name, \"Received RTCP BYE, reason: %.*s\",\n\t       reason.slen, reason.ptr));\n}",
        "vulnerability": "Untrusted Data",
        "reason": "The code blindly copies the reason string from the packet to the peer_sdes_buf_ without validating its content. This can be exploited by an attacker to inject malicious data into the peer_sdes_buf_, potentially leading to further exploitation or data corruption. An attacker could send a crafted RTCP BYE packet with a malicious reason string containing harmful data.",
        "file_name": "355014.sol"
    },
    {
        "function_name": "parse_rtcp_bye",
        "code": "static void parse_rtcp_bye(pjmedia_rtcp_session *sess,\n\t\t\t   const void *pkt,\n\t\t\t   pj_size_t size)\n{\n    pj_str_t reason = {\"-\", 1};\n    if (size > 8) {\n\treason.slen = PJ_MIN(sizeof(sess->stat.peer_sdes_buf_),\n                             *((pj_uint8_t*)pkt+8));\n        reason.slen = PJ_MIN(reason.slen, size-9);\n\tpj_memcpy(sess->stat.peer_sdes_buf_, ((pj_uint8_t*)pkt+9),\n\t\t  reason.slen);\n\treason.ptr = sess->stat.peer_sdes_buf_;\n    }\n    PJ_LOG(5, (sess->name, \"Received RTCP BYE, reason: %.*s\",\n\t       reason.slen, reason.ptr));\n}",
        "vulnerability": "Information Disclosure",
        "reason": "The code logs the reason string received in the RTCP BYE packet without any sanitization or filtering. This can lead to sensitive information disclosure if the reason string contains confidential data. An attacker could send a RTCP BYE packet with a reason string containing sensitive information, which would then be logged by the system, potentially exposing confidential data to unauthorized parties.",
        "file_name": "355014.sol"
    },
    {
        "function_name": "parse_rtcp_bye",
        "code": "static void parse_rtcp_bye(pjmedia_rtcp_session *sess,\n\t\t\t   const void *pkt,\n\t\t\t   pj_size_t size)\n{\n    pj_str_t reason = {\"-\", 1};\n    if (size > 8) {\n\treason.slen = PJ_MIN(sizeof(sess->stat.peer_sdes_buf_),\n                             *((pj_uint8_t*)pkt+8));\n        reason.slen = PJ_MIN(reason.slen, size-9);\n\tpj_memcpy(sess->stat.peer_sdes_buf_, ((pj_uint8_t*)pkt+9),\n\t\t  reason.slen);\n\treason.ptr = sess->stat.peer_sdes_buf_;\n    }\n    PJ_LOG(5, (sess->name, \"Received RTCP BYE, reason: %.*s\",\n\t       reason.slen, reason.ptr));\n}",
        "vulnerability": "Buffer Overflow",
        "reason": "The code does not perform proper bounds checking when copying data from the packet into the peer_sdes_buf_ buffer. An attacker could craft a malicious packet with a size larger than 8, causing a buffer overflow and potentially overwriting critical data or executing arbitrary code.",
        "file_name": "355014.sol"
    },
    {
        "function_name": "parse_rtcp_bye",
        "code": "static void parse_rtcp_bye(pjmedia_rtcp_session *sess,\n\t\t\t   const void *pkt,\n\t\t\t   pj_size_t size)\n{\n    pj_str_t reason = {\"-\", 1};\n    if (size > 8) {\n\treason.slen = PJ_MIN(sizeof(sess->stat.peer_sdes_buf_),\n                             *((pj_uint8_t*)pkt+8));\n        reason.slen = PJ_MIN(reason.slen, size-9);\n\tpj_memcpy(sess->stat.peer_sdes_buf_, ((pj_uint8_t*)pkt+9),\n\t\t  reason.slen);\n\treason.ptr = sess->stat.peer_sdes_buf_;\n    }\n    PJ_LOG(5, (sess->name, \"Received RTCP BYE, reason: %.*s\",\n\t       reason.slen, reason.ptr));\n}",
        "vulnerability": "Untrusted Input",
        "reason": "The code blindly trusts the size parameter provided by the packet without verifying its authenticity. An attacker could manipulate the size value to be larger than the actual size of the packet, leading to potential data leakage or denial of service.",
        "file_name": "355014.sol"
    },
    {
        "function_name": "parse_rtcp_bye",
        "code": "static void parse_rtcp_bye(pjmedia_rtcp_session *sess,\n\t\t\t   const void *pkt,\n\t\t\t   pj_size_t size)\n{\n    pj_str_t reason = {\"-\", 1};\n    if (size > 8) {\n\treason.slen = PJ_MIN(sizeof(sess->stat.peer_sdes_buf_),\n                             *((pj_uint8_t*)pkt+8));\n        reason.slen = PJ_MIN(reason.slen, size-9);\n\tpj_memcpy(sess->stat.peer_sdes_buf_, ((pj_uint8_t*)pkt+9),\n\t\t  reason.slen);\n\treason.ptr = sess->stat.peer_sdes_buf_;\n    }\n    PJ_LOG(5, (sess->name, \"Received RTCP BYE, reason: %.*s\",\n\t       reason.slen, reason.ptr));\n}",
        "vulnerability": "Information Disclosure",
        "reason": "The code logs the received RTCP BYE packet's reason without any sanitization or validation. An attacker could exploit this to leak sensitive information stored in the reason field, such as user credentials or system details, aiding in further attacks.",
        "file_name": "355014.sol"
    }
]