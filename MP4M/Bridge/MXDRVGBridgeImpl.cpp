//
//  MXDRVGBridgeImpl.cpp
//  C++ ロジック実装 (LZX展開、MDXロード)
//

#include "MXDRVGBridgeImpl.h"
#include "mxdrvg.h"
#include "lzx.h"
#include <cstdlib>
#include <cstring>

// グローバル状態
static uint8_t* g_mdxData = nullptr;
static size_t g_mdxDataLen = 0;
static uint8_t* g_pdxData = nullptr;
static size_t g_pdxDataLen = 0;
static char g_lastTitle[512] = {0};
static int g_totalPlayTimeMs = 0;

// LZX 展開
static uint8_t* decompressIfLZX(const uint8_t* data, size_t len, size_t& outLen) {
    if (len < 0x16) {
        outLen = len;
        uint8_t* buf = (uint8_t*)malloc(len);
        if (buf) memcpy(buf, data, len);
        return buf;
    }

    unsigned int decompLen = lzx::check(data, len);
    if (decompLen == 0) {
        outLen = len;
        uint8_t* buf = (uint8_t*)malloc(len);
        if (buf) memcpy(buf, data, len);
        return buf;
    }

    static const unsigned int MAX_DECOMP_SIZE = 1 * 1024 * 1024;
    if (decompLen > MAX_DECOMP_SIZE) {
        return nullptr;
    }

    uint8_t* buf = (uint8_t*)malloc(decompLen);
    if (!buf) return nullptr;

    unsigned int ret = lzx::decompress(buf, decompLen, data, len);
    if (ret == 0) {
        free(buf);
        return nullptr;
    }

    outLen = ret;
    return buf;
}

// MXDRVG ヘッダー付与
static uint8_t* wrapMDX(const uint8_t* body, size_t bodyLen, bool hasPDX, size_t& outLen) {
    uint8_t hdr[10] = {
        0x00, 0x00,
        (uint8_t)(hasPDX ? 0x00 : 0xff),
        (uint8_t)(hasPDX ? 0x00 : 0xff),
        0x00, 0x0a, 0x00, 0x08, 0x00, 0x00
    };

    outLen = 10 + bodyLen;
    uint8_t* out = (uint8_t*)malloc(outLen);
    if (!out) return nullptr;

    memcpy(out, hdr, 10);
    memcpy(out + 10, body, bodyLen);
    return out;
}

static uint8_t* wrapPDX(const uint8_t* body, size_t bodyLen, size_t& outLen) {
    uint8_t hdr[10] = {0x00, 0x00, 0x00, 0x00, 0x00, 0x0a, 0x00, 0x02, 0x00, 0x00};

    outLen = 10 + bodyLen;
    uint8_t* out = (uint8_t*)malloc(outLen);
    if (!out) return nullptr;

    memcpy(out, hdr, 10);
    memcpy(out + 10, body, bodyLen);
    return out;
}

// Shift-JIS → UTF-8 変換
static const char* shiftJISToUTF8(const uint8_t* sjisStr, size_t maxLen) {
    memset(g_lastTitle, 0, sizeof(g_lastTitle));

    size_t outIdx = 0;
    for (size_t i = 0; i < maxLen && outIdx < sizeof(g_lastTitle) - 1; i++) {
        uint8_t c = sjisStr[i];
        if (c == 0) break;
        if (c < 128) {
            g_lastTitle[outIdx++] = (char)c;
        } else {
            g_lastTitle[outIdx++] = '?';
            if (i + 1 < maxLen) i++;
        }
    }
    g_lastTitle[outIdx] = 0;
    return g_lastTitle[0] ? g_lastTitle : "(no title)";
}

// MDX ロード実装
extern "C" {

const char* MXDRVGBridgeImpl_LoadMDXData(const uint8_t* mdxRaw, size_t mdxRawLen,
                                        const uint8_t* pdxRaw, size_t pdxRawLen) {
    if (!mdxRaw || mdxRawLen < 5) {
        return nullptr;
    }

    const uint8_t* p = mdxRaw;
    int pos = 0;
    for (; pos + 1 < (int)mdxRawLen; pos++) {
        if (p[pos] == 0x0d && p[pos + 1] == 0x0a) break;
    }
    if (pos >= (int)mdxRawLen - 1) {
        return nullptr;
    }

    const char* title = shiftJISToUTF8(p, pos);

    size_t mdxBodyLen = 0;
    uint8_t* mdxBody = nullptr;
    {
        const uint8_t* mdxStart = p + pos + 2;
        if (*mdxStart != 0x1A) {
            return nullptr;
        }
        mdxStart++;

        while (mdxStart < p + mdxRawLen && *mdxStart != 0) {
            mdxStart++;
        }
        mdxStart++;

        size_t remaining = mdxRawLen - (mdxStart - p);
        mdxBody = decompressIfLZX(mdxStart, remaining, mdxBodyLen);
    }

    if (!mdxBody) {
        return nullptr;
    }

    size_t pdxWrappedLen = 0;
    uint8_t* pdxWrapped = nullptr;
    bool hasPDX = (pdxRaw && pdxRawLen > 0);

    if (hasPDX) {
        size_t pdxBodyLen = 0;
        uint8_t* pdxBody = decompressIfLZX(pdxRaw, pdxRawLen, pdxBodyLen);
        if (!pdxBody) {
            free(mdxBody);
            return nullptr;
        }
        pdxWrapped = wrapPDX(pdxBody, pdxBodyLen, pdxWrappedLen);
        free(pdxBody);
    }

    size_t mdxWrappedLen = 0;
    uint8_t* mdxWrapped = wrapMDX(mdxBody, mdxBodyLen, hasPDX, mdxWrappedLen);
    free(mdxBody);

    if (!mdxWrapped) {
        if (pdxWrapped) free(pdxWrapped);
        return nullptr;
    }

    if (g_mdxData) free(g_mdxData);
    if (g_pdxData) free(g_pdxData);

    g_mdxData = mdxWrapped;
    g_mdxDataLen = mdxWrappedLen;
    g_pdxData = pdxWrapped;
    g_pdxDataLen = pdxWrappedLen;

    return title;
}

void MXDRVGBridgeImpl_GetMDXData(uint8_t** mdx, size_t* mdxLen, uint8_t** pdx, size_t* pdxLen) {
    if (mdx) *mdx = g_mdxData;
    if (mdxLen) *mdxLen = g_mdxDataLen;
    if (pdx) *pdx = g_pdxData;
    if (pdxLen) *pdxLen = g_pdxDataLen;
}

void MXDRVGBridgeImpl_FreeMDXData(void) {
    if (g_mdxData) {
        free(g_mdxData);
        g_mdxData = nullptr;
    }
    if (g_pdxData) {
        free(g_pdxData);
        g_pdxData = nullptr;
    }
}

int MXDRVGBridgeImpl_GetTotalPlayTimeMs(void) {
    return g_totalPlayTimeMs;
}

void MXDRVGBridgeImpl_SetTotalPlayTimeMs(int ms) {
    g_totalPlayTimeMs = ms;
}

}  // extern "C"
