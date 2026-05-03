//
//  MXDRVGBridgeImpl.h
//  C++ ロジック用 C インターフェース
//

#ifndef MXDRVGBRIDGEIMPL_H
#define MXDRVGBRIDGEIMPL_H

#include <stdint.h>
#include <stddef.h>

#ifdef __cplusplus
extern "C" {
#endif

const char* MXDRVGBridgeImpl_LoadMDXData(const uint8_t* mdxRaw, size_t mdxRawLen,
                                        const uint8_t* pdxRaw, size_t pdxRawLen);

void MXDRVGBridgeImpl_GetMDXData(uint8_t** mdx, size_t* mdxLen, uint8_t** pdx, size_t* pdxLen);

void MXDRVGBridgeImpl_FreeMDXData(void);

int MXDRVGBridgeImpl_GetTotalPlayTimeMs(void);

void MXDRVGBridgeImpl_SetTotalPlayTimeMs(int ms);

#ifdef __cplusplus
}
#endif

#endif // MXDRVGBRIDGEIMPL_H
