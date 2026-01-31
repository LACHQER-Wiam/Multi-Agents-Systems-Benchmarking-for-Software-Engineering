[
    {
        "function_name": "HandleCoRREBPP",
        "code": "HandleCoRREBPP (rfbClient* client, int rx, int ry, int rw, int rh)\n{\n    rfbRREHeader hdr;\n    int i;\n    CARDBPP pix;\n    uint8_t *ptr;\n    int x, y, w, h;\n    if (!ReadFromRFBServer(client, (char *)&hdr, sz_rfbRREHeader))\n\treturn FALSE;\n    hdr.nSubrects = rfbClientSwap32IfLE(hdr.nSubrects);\n    if (!ReadFromRFBServer(client, (char *)&pix, sizeof(pix)))\n\treturn FALSE;\n    client->GotFillRect(client, rx, ry, rw, rh, pix);\n    if (hdr.nSubrects * (4 + (BPP / 8)) > RFB_BUFFER_SIZE || !ReadFromRFBServer(client, client->buffer, hdr.nSubrects * (4 + (BPP / 8))))\n\treturn FALSE;\n    ptr = (uint8_t *)client->buffer;\n    for (i = 0; i < hdr.nSubrects; i++) {\n\tpix = *(CARDBPP *)ptr;\n\tptr += BPP/8;\n\tx = *ptr++;\n\ty = *ptr++;\n\tw = *ptr++;\n\th = *ptr++;\n\tclient->GotFillRect(client, rx+x, ry+y, w, h, pix);\n    }\n    return TRUE;\n}",
        "vulnerability": "Integer Overflow/Buffer Overflow",
        "reason": "The calculation 'hdr.nSubrects * (4 + (BPP / 8))' could lead to an integer overflow if 'hdr.nSubrects' is large enough. This can cause the buffer size check to be bypassed, leading to a potential buffer overflow when reading data into 'client->buffer'. An attacker could exploit this by sending a specially crafted message with a large 'nSubrects' value, causing arbitrary data to overflow into adjacent memory.",
        "file_name": "214003.sol"
    },
    {
        "function_name": "HandleCoRREBPP",
        "code": "HandleCoRREBPP (rfbClient* client, int rx, int ry, int rw, int rh)\n{\n    rfbRREHeader hdr;\n    int i;\n    CARDBPP pix;\n    uint8_t *ptr;\n    int x, y, w, h;\n    if (!ReadFromRFBServer(client, (char *)&hdr, sz_rfbRREHeader))\n\treturn FALSE;\n    hdr.nSubrects = rfbClientSwap32IfLE(hdr.nSubrects);\n    if (!ReadFromRFBServer(client, (char *)&pix, sizeof(pix)))\n\treturn FALSE;\n    client->GotFillRect(client, rx, ry, rw, rh, pix);\n    if (hdr.nSubrects * (4 + (BPP / 8)) > RFB_BUFFER_SIZE || !ReadFromRFBServer(client, client->buffer, hdr.nSubrects * (4 + (BPP / 8))))\n\treturn FALSE;\n    ptr = (uint8_t *)client->buffer;\n    for (i = 0; i < hdr.nSubrects; i++) {\n\tpix = *(CARDBPP *)ptr;\n\tptr += BPP/8;\n\tx = *ptr++;\n\ty = *ptr++;\n\tw = *ptr++;\n\th = *ptr++;\n\tclient->GotFillRect(client, rx+x, ry+y, w, h, pix);\n    }\n    return TRUE;\n}",
        "vulnerability": "Out-of-Bounds Read",
        "reason": "The code reads from the buffer 'client->buffer' using the pointer 'ptr' without checking whether the buffer has enough data to read 4 bytes for each subrectangle. If 'hdr.nSubrects' is large or manipulated by an attacker, 'ptr' could exceed the buffer's boundary, leading to an out-of-bounds read. This could potentially leak sensitive information or cause a crash, which can be further exploited.",
        "file_name": "214003.sol"
    },
    {
        "function_name": "HandleCoRREBPP",
        "code": "HandleCoRREBPP (rfbClient* client, int rx, int ry, int rw, int rh)\n{\n    rfbRREHeader hdr;\n    int i;\n    CARDBPP pix;\n    uint8_t *ptr;\n    int x, y, w, h;\n    if (!ReadFromRFBServer(client, (char *)&hdr, sz_rfbRREHeader))\n\treturn FALSE;\n    hdr.nSubrects = rfbClientSwap32IfLE(hdr.nSubrects);\n    if (!ReadFromRFBServer(client, (char *)&pix, sizeof(pix)))\n\treturn FALSE;\n    client->GotFillRect(client, rx, ry, rw, rh, pix);\n    if (hdr.nSubrects * (4 + (BPP / 8)) > RFB_BUFFER_SIZE || !ReadFromRFBServer(client, client->buffer, hdr.nSubrects * (4 + (BPP / 8))))\n\treturn FALSE;\n    ptr = (uint8_t *)client->buffer;\n    for (i = 0; i < hdr.nSubrects; i++) {\n\tpix = *(CARDBPP *)ptr;\n\tptr += BPP/8;\n\tx = *ptr++;\n\ty = *ptr++;\n\tw = *ptr++;\n\th = *ptr++;\n\tclient->GotFillRect(client, rx+x, ry+y, w, h, pix);\n    }\n    return TRUE;\n}",
        "vulnerability": "Improper Input Validation",
        "reason": "The values 'x', 'y', 'w', and 'h' are derived directly from the buffer data without validation. An attacker could craft a message that sets these values to extreme numbers, causing the function 'client->GotFillRect' to operate on unintended memory regions. This can lead to arbitrary code execution or memory corruption.",
        "file_name": "214003.sol"
    },
    {
        "function_name": "HandleCoRREBPP",
        "code": "HandleCoRREBPP (rfbClient* client, int rx, int ry, int rw, int rh)\n{\n    rfbRREHeader hdr;\n    int i;\n    CARDBPP pix;\n    uint8_t *ptr;\n    int x, y, w, h;\n    if (!ReadFromRFBServer(client, (char *)&hdr, sz_rfbRREHeader))\n\treturn FALSE;\n    hdr.nSubrects = rfbClientSwap32IfLE(hdr.nSubrects);\n    if (!ReadFromRFBServer(client, (char *)&pix, sizeof(pix)))\n\treturn FALSE;\n    client->GotFillRect(client, rx, ry, rw, rh, pix);\n    if (hdr.nSubrects * (4 + (BPP / 8)) > RFB_BUFFER_SIZE || !ReadFromRFBServer(client, client->buffer, hdr.nSubrects * (4 + (BPP / 8))))\n\treturn FALSE;\n    ptr = (uint8_t *)client->buffer;\n    for (i = 0; i < hdr.nSubrects; i++) {\n\tpix = *(CARDBPP *)ptr;\n\tptr += BPP/8;\n\tx = *ptr++;\n\ty = *ptr++;\n\tw = *ptr++;\n\th = *ptr++;\n\tclient->GotFillRect(client, rx+x, ry+y, w, h, pix);\n    }\n    return TRUE;\n}",
        "vulnerability": "Buffer Overflow",
        "reason": "The function reads data into client->buffer based on hdr.nSubrects without verifying if the buffer is large enough to handle the data. If hdr.nSubrects is large enough, this could lead to a buffer overflow, potentially allowing attackers to execute arbitrary code or crash the application.",
        "file_name": "214003.sol"
    },
    {
        "function_name": "HandleCoRREBPP",
        "code": "HandleCoRREBPP (rfbClient* client, int rx, int ry, int rw, int rh)\n{\n    rfbRREHeader hdr;\n    int i;\n    CARDBPP pix;\n    uint8_t *ptr;\n    int x, y, w, h;\n    if (!ReadFromRFBServer(client, (char *)&hdr, sz_rfbRREHeader))\n\treturn FALSE;\n    hdr.nSubrects = rfbClientSwap32IfLE(hdr.nSubrects);\n    if (!ReadFromRFBServer(client, (char *)&pix, sizeof(pix)))\n\treturn FALSE;\n    client->GotFillRect(client, rx, ry, rw, rh, pix);\n    if (hdr.nSubrects * (4 + (BPP / 8)) > RFB_BUFFER_SIZE || !ReadFromRFBServer(client, client->buffer, hdr.nSubrects * (4 + (BPP / 8))))\n\treturn FALSE;\n    ptr = (uint8_t *)client->buffer;\n    for (i = 0; i < hdr.nSubrects; i++) {\n\tpix = *(CARDBPP *)ptr;\n\tptr += BPP/8;\n\tx = *ptr++;\n\ty = *ptr++;\n\tw = *ptr++;\n\th = *ptr++;\n\tclient->GotFillRect(client, rx+x, ry+y, w, h, pix);\n    }\n    return TRUE;\n}",
        "vulnerability": "Integer Overflow",
        "reason": "The calculation of the pointer increment (ptr += BPP/8) and subsequent pointer arithmetic do not account for potential integer overflow. If BPP is set to a large value, or if ptr is near the boundary of the address space, this could lead to invalid memory access, which attackers can exploit to corrupt memory or execute arbitrary code.",
        "file_name": "214003.sol"
    },
    {
        "function_name": "HandleCoRREBPP",
        "code": "HandleCoRREBPP (rfbClient* client, int rx, int ry, int rw, int rh)\n{\n    rfbRREHeader hdr;\n    int i;\n    CARDBPP pix;\n    uint8_t *ptr;\n    int x, y, w, h;\n    if (!ReadFromRFBServer(client, (char *)&hdr, sz_rfbRREHeader))\n\treturn FALSE;\n    hdr.nSubrects = rfbClientSwap32IfLE(hdr.nSubrects);\n    if (!ReadFromRFBServer(client, (char *)&pix, sizeof(pix)))\n\treturn FALSE;\n    client->GotFillRect(client, rx, ry, rw, rh, pix);\n    if (hdr.nSubrects * (4 + (BPP / 8)) > RFB_BUFFER_SIZE || !ReadFromRFBServer(client, client->buffer, hdr.nSubrects * (4 + (BPP / 8))))\n\treturn FALSE;\n    ptr = (uint8_t *)client->buffer;\n    for (i = 0; i < hdr.nSubrects; i++) {\n\tpix = *(CARDBPP *)ptr;\n\tptr += BPP/8;\n\tx = *ptr++;\n\ty = *ptr++;\n\tw = *ptr++;\n\th = *ptr++;\n\tclient->GotFillRect(client, rx+x, ry+y, w, h, pix);\n    }\n    return TRUE;\n}",
        "vulnerability": "Lack of Bounds Checking",
        "reason": "There is no validation on hdr.nSubrects after it is swapped for endianness. An attacker could manipulate the number of subrectangles to be excessively large, leading to excessive memory allocation or overflows in subsequent calculations, which can be exploited to compromise the system.",
        "file_name": "214003.sol"
    }
]