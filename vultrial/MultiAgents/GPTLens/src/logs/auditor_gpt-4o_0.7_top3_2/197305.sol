[
    {
        "function_name": "pjmedia_rtcp_fb_parse_rpsi",
        "code": "PJ_DEF(pj_status_t) pjmedia_rtcp_fb_parse_rpsi(\n\t\t\t\t\tconst void *buf,\n\t\t\t\t\tpj_size_t length,\n\t\t\t\t\tpjmedia_rtcp_fb_rpsi *rpsi)\n{\n    pjmedia_rtcp_common *hdr = (pjmedia_rtcp_common*) buf;\n    pj_uint8_t *p;\n    pj_uint8_t padlen;\n    pj_size_t rpsi_len;\n    PJ_ASSERT_RETURN(buf && rpsi, PJ_EINVAL);\n    PJ_ASSERT_RETURN(length >= sizeof(pjmedia_rtcp_common), PJ_ETOOSMALL);\n    if (hdr->pt != RTCP_PSFB || hdr->count != 3)\n\treturn PJ_ENOTFOUND;\n    rpsi_len = (pj_ntohs((pj_uint16_t)hdr->length)-2) * 4;\n    if (length < rpsi_len + 12)\n\treturn PJ_ETOOSMALL;\n    p = (pj_uint8_t*)hdr + sizeof(*hdr);\n    padlen = *p++;\n    rpsi->pt = (*p++ & 0x7F);\n    rpsi->rpsi_bit_len = rpsi_len*8 - 16 - padlen;\n    pj_strset(&rpsi->rpsi, (char*)p, (rpsi->rpsi_bit_len + 7)/8);\n    return PJ_SUCCESS;\n}",
        "vulnerability": "Integer Underflow",
        "reason": "The calculation of rpsi_len = (pj_ntohs((pj_uint16_t)hdr->length)-2) * 4 can result in an integer underflow if hdr->length is less than 2. This could lead to an incorrect, large positive number for rpsi_len and potentially allow attackers to bypass the length check, leading to buffer overflow when accessing p.",
        "file_name": "197305.sol"
    },
    {
        "function_name": "pjmedia_rtcp_fb_parse_rpsi",
        "code": "PJ_DEF(pj_status_t) pjmedia_rtcp_fb_parse_rpsi(\n\t\t\t\t\tconst void *buf,\n\t\t\t\t\tpj_size_t length,\n\t\t\t\t\tpjmedia_rtcp_fb_rpsi *rpsi)\n{\n    pjmedia_rtcp_common *hdr = (pjmedia_rtcp_common*) buf;\n    pj_uint8_t *p;\n    pj_uint8_t padlen;\n    pj_size_t rpsi_len;\n    PJ_ASSERT_RETURN(buf && rpsi, PJ_EINVAL);\n    PJ_ASSERT_RETURN(length >= sizeof(pjmedia_rtcp_common), PJ_ETOOSMALL);\n    if (hdr->pt != RTCP_PSFB || hdr->count != 3)\n\treturn PJ_ENOTFOUND;\n    rpsi_len = (pj_ntohs((pj_uint16_t)hdr->length)-2) * 4;\n    if (length < rpsi_len + 12)\n\treturn PJ_ETOOSMALL;\n    p = (pj_uint8_t*)hdr + sizeof(*hdr);\n    padlen = *p++;\n    rpsi->pt = (*p++ & 0x7F);\n    rpsi->rpsi_bit_len = rpsi_len*8 - 16 - padlen;\n    pj_strset(&rpsi->rpsi, (char*)p, (rpsi->rpsi_bit_len + 7)/8);\n    return PJ_SUCCESS;\n}",
        "vulnerability": "Buffer Overflow",
        "reason": "The function uses a calculated value rpsi->rpsi_bit_len to determine the size of data to be copied using pj_strset. If this length is incorrectly calculated due to manipulated input, it can lead to buffer overflow when writing to rpsi->rpsi, especially since there are no checks ensuring this length is within the allocated space for rpsi->rpsi.",
        "file_name": "197305.sol"
    },
    {
        "function_name": "pjmedia_rtcp_fb_parse_rpsi",
        "code": "PJ_DEF(pj_status_t) pjmedia_rtcp_fb_parse_rpsi(\n\t\t\t\t\tconst void *buf,\n\t\t\t\t\tpj_size_t length,\n\t\t\t\t\tpjmedia_rtcp_fb_rpsi *rpsi)\n{\n    pjmedia_rtcp_common *hdr = (pjmedia_rtcp_common*) buf;\n    pj_uint8_t *p;\n    pj_uint8_t padlen;\n    pj_size_t rpsi_len;\n    PJ_ASSERT_RETURN(buf && rpsi, PJ_EINVAL);\n    PJ_ASSERT_RETURN(length >= sizeof(pjmedia_rtcp_common), PJ_ETOOSMALL);\n    if (hdr->pt != RTCP_PSFB || hdr->count != 3)\n\treturn PJ_ENOTFOUND;\n    rpsi_len = (pj_ntohs((pj_uint16_t)hdr->length)-2) * 4;\n    if (length < rpsi_len + 12)\n\treturn PJ_ETOOSMALL;\n    p = (pj_uint8_t*)hdr + sizeof(*hdr);\n    padlen = *p++;\n    rpsi->pt = (*p++ & 0x7F);\n    rpsi->rpsi_bit_len = rpsi_len*8 - 16 - padlen;\n    pj_strset(&rpsi->rpsi, (char*)p, (rpsi->rpsi_bit_len + 7)/8);\n    return PJ_SUCCESS;\n}",
        "vulnerability": "Improper Validation of Input",
        "reason": "The function does not adequately validate the contents of the incoming buffer, particularly the hdr->length field, before using it in calculations. An attacker could craft a buffer with a malicious hdr->length value to manipulate the flow of execution or cause incorrect memory operations.",
        "file_name": "197305.sol"
    },
    {
        "function_name": "pjmedia_rtcp_fb_parse_rpsi",
        "code": "PJ_DEF(pj_status_t) pjmedia_rtcp_fb_parse_rpsi(\n\t\t\t\t\tconst void *buf,\n\t\t\t\t\tpj_size_t length,\n\t\t\t\t\tpjmedia_rtcp_fb_rpsi *rpsi)\n{\n    pjmedia_rtcp_common *hdr = (pjmedia_rtcp_common*) buf;\n    pj_uint8_t *p;\n    pj_uint8_t padlen;\n    pj_size_t rpsi_len;\n    PJ_ASSERT_RETURN(buf && rpsi, PJ_EINVAL);\n    PJ_ASSERT_RETURN(length >= sizeof(pjmedia_rtcp_common), PJ_ETOOSMALL);\n    if (hdr->pt != RTCP_PSFB || hdr->count != 3)\n\treturn PJ_ENOTFOUND;\n    rpsi_len = (pj_ntohs((pj_uint16_t)hdr->length)-2) * 4;\n    if (length < rpsi_len + 12)\n\treturn PJ_ETOOSMALL;\n    p = (pj_uint8_t*)hdr + sizeof(*hdr);\n    padlen = *p++;\n    rpsi->pt = (*p++ & 0x7F);\n    rpsi->rpsi_bit_len = rpsi_len*8 - 16 - padlen;\n    pj_strset(&rpsi->rpsi, (char*)p, (rpsi->rpsi_bit_len + 7)/8);\n    return PJ_SUCCESS;\n}",
        "vulnerability": "Integer Underflow",
        "reason": "The calculation `pj_ntohs((pj_uint16_t)hdr->length)-2` can lead to an integer underflow if `hdr->length` is less than 2. This underflow would cause `rpsi_len` to become a large value, potentially bypassing the length check `if (length < rpsi_len + 12)`, leading to a buffer overflow vulnerability.",
        "file_name": "197305.sol"
    },
    {
        "function_name": "pjmedia_rtcp_fb_parse_rpsi",
        "code": "PJ_DEF(pj_status_t) pjmedia_rtcp_fb_parse_rpsi(\n\t\t\t\t\tconst void *buf,\n\t\t\t\t\tpj_size_t length,\n\t\t\t\t\tpjmedia_rtcp_fb_rpsi *rpsi)\n{\n    pjmedia_rtcp_common *hdr = (pjmedia_rtcp_common*) buf;\n    pj_uint8_t *p;\n    pj_uint8_t padlen;\n    pj_size_t rpsi_len;\n    PJ_ASSERT_RETURN(buf && rpsi, PJ_EINVAL);\n    PJ_ASSERT_RETURN(length >= sizeof(pjmedia_rtcp_common), PJ_ETOOSMALL);\n    if (hdr->pt != RTCP_PSFB || hdr->count != 3)\n\treturn PJ_ENOTFOUND;\n    rpsi_len = (pj_ntohs((pj_uint16_t)hdr->length)-2) * 4;\n    if (length < rpsi_len + 12)\n\treturn PJ_ETOOSMALL;\n    p = (pj_uint8_t*)hdr + sizeof(*hdr);\n    padlen = *p++;\n    rpsi->pt = (*p++ & 0x7F);\n    rpsi->rpsi_bit_len = rpsi_len*8 - 16 - padlen;\n    pj_strset(&rpsi->rpsi, (char*)p, (rpsi->rpsi_bit_len + 7)/8);\n    return PJ_SUCCESS;\n}",
        "vulnerability": "Improper Validation of Data",
        "reason": "The `padlen` value is extracted from the buffer without any validation. If `padlen` is larger than `rpsi_len*8 - 16`, it would result in an incorrect `rpsi->rpsi_bit_len`, potentially leading to unexpected behavior when this value is used later in the function. This could be exploited by an attacker to manipulate the parsed data structure in unpredictable ways.",
        "file_name": "197305.sol"
    },
    {
        "function_name": "pjmedia_rtcp_fb_parse_rpsi",
        "code": "PJ_DEF(pj_status_t) pjmedia_rtcp_fb_parse_rpsi(\n\t\t\t\t\tconst void *buf,\n\t\t\t\t\tpj_size_t length,\n\t\t\t\t\tpjmedia_rtcp_fb_rpsi *rpsi)\n{\n    pjmedia_rtcp_common *hdr = (pjmedia_rtcp_common*) buf;\n    pj_uint8_t *p;\n    pj_uint8_t padlen;\n    pj_size_t rpsi_len;\n    PJ_ASSERT_RETURN(buf && rpsi, PJ_EINVAL);\n    PJ_ASSERT_RETURN(length >= sizeof(pjmedia_rtcp_common), PJ_ETOOSMALL);\n    if (hdr->pt != RTCP_PSFB || hdr->count != 3)\n\treturn PJ_ENOTFOUND;\n    rpsi_len = (pj_ntohs((pj_uint16_t)hdr->length)-2) * 4;\n    if (length < rpsi_len + 12)\n\treturn PJ_ETOOSMALL;\n    p = (pj_uint8_t*)hdr + sizeof(*hdr);\n    padlen = *p++;\n    rpsi->pt = (*p++ & 0x7F);\n    rpsi->rpsi_bit_len = rpsi_len*8 - 16 - padlen;\n    pj_strset(&rpsi->rpsi, (char*)p, (rpsi->rpsi_bit_len + 7)/8);\n    return PJ_SUCCESS;\n}",
        "vulnerability": "Buffer Overflow",
        "reason": "The `pj_strset` function copies data from the buffer to `rpsi->rpsi` using the calculated length `(rpsi->rpsi_bit_len + 7)/8`. If `rpsi_bit_len` is miscalculated due to previous vulnerabilities or improper input, this can lead to a buffer overflow, allowing an attacker to overwrite memory beyond the intended buffer, potentially leading to code execution or denial of service.",
        "file_name": "197305.sol"
    }
]