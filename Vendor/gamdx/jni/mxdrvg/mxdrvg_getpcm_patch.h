int MXDRVG_GetPCM(
	SWORD *buf,
	int len
) {
	static Sample *innerbuf = NULL;
	static ULONG innerbuflen = 0;
	int rest_len = len;
	Sample *outerbuf = (Sample *)buf;

	if (len > 1024) return (0);
	if (G.SAMPRATE == 0) return (0);

	// 初期化: 最初の割り込みでシーケンサーを起動
	static int first_call = 1;
	if (first_call) {
		first_call = 0;
		OPMINTFUNC();
	}

	while (rest_len > 0) {
		ULONG create_len = 1;  // 1サンプルずつ生成
		ULONG create_len2 = DS.GetInSamplesForDownSample(create_len);
		if (innerbuflen < create_len2) {
			if (innerbuf) free(innerbuf);
			innerbuflen = create_len2*2;
			innerbuf = (Sample *)malloc(innerbuflen * sizeof(Sample) * 2);
		}
		if (innerbuf) {
			memset(innerbuf, 0, create_len2*sizeof(Sample)*2);
			OPM_MixWrapper((int16_t *)innerbuf, create_len2);
			PCM8.Mix(innerbuf, create_len2);
			if (TotalVolume != 256) {
				for (ULONG j=0; j<create_len2; j++) {
					int v0 = (innerbuf[j*2+0] * TotalVolume) >> 8;
					int v1 = (innerbuf[j*2+1] * TotalVolume) >> 8;
					if (v0 < -32768) v0 = -32768;
					if (v1 < -32768) v1 = -32768;
					if (v0 > 32767) v0 = 32767;
					if (v1 > 32767) v1 = 32767;
					innerbuf[j*2+0] = v0;
					innerbuf[j*2+1] = v1;
				}
			}
			DS.DownSample(innerbuf, create_len, outerbuf);
			outerbuf += create_len*2;
		}
		G.PLAYSAMPLES += create_len;
		G.PLAYTIME += (create_len*1000)/G.SAMPRATE;
		
		// 一定サンプルごとに割り込み（約61Hz）
		static ULONG sample_counter = 0;
		sample_counter += create_len;
		if (sample_counter >= (G.SAMPRATE / 61)) {
			OPMINTFUNC();
			sample_counter = 0;
		}
		
		rest_len -= create_len;
	}

	return (len);
}
