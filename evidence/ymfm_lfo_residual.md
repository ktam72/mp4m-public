# ymfm エンジンにおける MDX 再生の音色不定再現問題

## 発現条件
- MXDRV + ymfm (OpmEngineYmfm) で MDX を再生
- PDX（PCMデータ）**なし**の FM のみの曲で発生
- 1回目の再生と2回目の再生で音色が異なる（再現性は間欠的）
- **fmgen (OpmEngineFmgen) では発生しない**

## 確認済みの事実

### トレースログ解析（SC88_044.MDX で検証）
- OPM レジスタ値の書き込みは1回目と2回目で**完全に同一**
- チャンネルシーケンスポインタ（S0000）の初期化は毎回同じ値を示す
- `L0007c0()` のチャンネル初期化は決定論的

### 試した修正と結果
| 修正 | 結果 |
|------|------|
| `g_engine->Reset()` を L00063e に追加 | 音が出ないチャンネルが発生 |
| `g_engine->Reset()` を playWithLoopCount に追加 | 同上 |
| 音色パラメータレジスタ($40-$DF)のクリアを L00063e に追加 | 音が出ないチャンネルが発生 |
| チャンネル未初期化フィールド(S0012,S0036等)の明示的クリア | 変化なし |
| オーディオスレッドとの競合防止(mutex) | 変化なし |
| LFO位相リセット($01 bit1 LFO RESET)書き込みの即時反映 | 変化なし |
| タイマーキックスタート付きエンジンReset | 一貫性は改善したが品質低下 |
| 音響系のみのResetSound (LFO/Noise)| 変化なし |

## 推測される原因
- ymfm エンジン内部の何らかの状態（LFO, Noise, エンベロープ、あるいは累積クロック）が MeasurePlayTime の Count ループにより再生間で異なる値になる
- この状態差が同じレジスタ書き込みでも微妙に異なる音響出力を生む
- fmgen は Count 内でタイマーを自動リロードする実装になっており、この問題が発生しない

## 応急処置
デフォルトエンジンを fmgen に変更（`AboutView.swift` のデフォルト値を 1 に設定）

## 関連ファイル
- `Vendor/ymfm/opm_wrapper.cpp` - OpmWrapper (Count, SetReg, Reset)
- `Vendor/ymfm/ymfm_opm.cpp` - opm_registers (reset, clock_noise_and_lfo)
- `Vendor/gamdx/jni/mxdrvg/mxdrvg_core.h` - MXDRV コアエミュレーション
- `MP4M/Bridge/MXDRVGBridge.mm` - ブリッジ (playWithLoopCount)
- `MP4M/Views/AboutView.swift` - エンジン選択UI
