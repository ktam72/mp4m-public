#include "lzx042.h"
#include <stddef.h>

/* LZXヘッダー最小サイズ: マジック(4byte@0x04) + 展開後サイズ(4byte@0x12) = 最低0x16byte必要 */
#define LZX_MIN_HEADER_SIZE 0x16

unsigned lzx042check(const unsigned char *pData)
{
	/* ヘッダーサイズチェック */
	if (!pData) return 0;

	/* マジック読み込み前に境界チェック */
	if (pData[4] != 0x4c || pData[5] != 0x5a || pData[6] != 0x58 || pData[7] != 0x20) return 0;

	/* 展開後サイズ読み込み前に境界チェック */
	return (((unsigned)pData[0x12]) << 24) + (((unsigned)pData[0x13]) << 16) + (((unsigned)pData[0x14]) << 8) + pData[0x15];
}

unsigned lzx042decode(unsigned char *pBuffer, unsigned uBufferLength, const unsigned char *pData, unsigned uDataLength)
{

#define CHECK_INPUT(n)		\
{							\
	if ((size_t)(sp - pData) + (n) > uDataLength) return (unsigned)(dp - dt);	\
}

#define GETBYTE(x)			\
{							\
	if (sp == se) return (unsigned)(dp - dt);	\
	x = *sp++;				\
}

#define GETBIT(x)				\
{								\
	if (bitnum-- == 0)			\
	{							\
		GETBYTE(bitbuf);		\
		bitnum = 7;				\
	}							\
	x = (bitbuf >> bitnum) & 1;	\
}

#define STOREBYTE(x)		\
{							\
	if (dp == de) return (unsigned)(dp - dt);	\
	*dp++ = x;				\
}

	signed char bitnum;
	unsigned char bitbuf;
	unsigned char *dt, *dp, *de;
	const unsigned char *st, *sp, *se;
	dt = dp = de = pBuffer;
	de += uBufferLength;
	st = sp = se = pData;
	se += uDataLength;

	/* ヘッダースキップ: 0x26バイト後にマジック 7F FF FF 4C を探す */
	/* 検索前に最小サイズチェック */
	if (uDataLength < 0x26 + 4) return 0;
	for (sp += 0x26; sp + 3 < se; sp += 2) {
		if (sp[0] == 0x7F && sp[1] == 0xFF && sp[2] == 0xFF && sp[3] == 0x4C) break;
	}
	if (sp + 3 >= se) return 0;
	sp += 4;

	bitbuf = bitnum = 0;
	while (1)
	{
		unsigned char bitwork;
		GETBIT(bitwork);
		if (bitwork)
		{
			unsigned char bytework;
			GETBYTE(bytework);
			STOREBYTE(bytework);
		}
		else
		{
			int offset;
			unsigned int count;
			GETBIT(bitwork);
			if (!bitwork)
			{
				GETBIT(count);
				GETBIT(bitwork);
				count = count + count + bitwork + 2;
				GETBYTE(offset);
				offset -= 1 << 8;
			}
			else
			{
		GETBYTE(offset);
		GETBYTE(count);
		offset = (offset << 5) + (count >> 3);
		offset -= (int)(1U << 13);
		count = (count & 7) + 2;
				if (count == 2)
				{
					GETBYTE(count);
					if (++count == 1) return (unsigned)(dp - dt);
				}
			}
			/* バッファ範囲外参照の防止 */
			if (offset <= 0 || dp + (unsigned)offset < dt) return (unsigned)(dp - dt);
			/* 書き込み先がバッファ末端を超えないようガード */
			if ((size_t)(dp - dt) + count > uBufferLength) return (unsigned)(dp - dt);
			for (unsigned int ci = 0; ci < count; ci++) {
				if (dp == de) break;
				unsigned char val = dp[offset];
				*dp = val;
				dp++;
			}
		}
	}
}
