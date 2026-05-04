#include <metal_stdlib>
using namespace metal;

struct ChannelState {
    uint8_t keyCode;
    uint8_t keyOffset;
    uint8_t velocity;
    uint8_t keyOn;
    uint8_t _pad[4];  // パディング（8バイト境界）
};

// コンピュートシェーダ：16 チャンネルのビンマッピング + 拡散を並列計算
kernel void computeSpectrum(
    device const ChannelState *channels [[buffer(0)]],
    device atomic_float *speaBuf [[buffer(1)]],
    uint id [[thread_position_in_grid]]
) {
    if (id >= 16) return;

    const ChannelState ch = channels[id];
    if (!ch.keyOn) return;

    int d = (ch.keyCode + ch.keyOffset) / 3;
    if (d >= 42) return;

    float x = float(ch.velocity);

    // ビンへの拡散処理（元の実装に準拠）
    atomic_fetch_add_explicit(&speaBuf[d], x, memory_order_relaxed);

    if (d > 0) {
        atomic_fetch_add_explicit(&speaBuf[d-1], x * 0.75f, memory_order_relaxed);
    }
    if (d < 51) {
        atomic_fetch_add_explicit(&speaBuf[d+1], x * 0.75f, memory_order_relaxed);
    }

    if (d > 1) {
        atomic_fetch_add_explicit(&speaBuf[d-2], x * 0.3125f, memory_order_relaxed);
    }
    if (d < 50) {
        atomic_fetch_add_explicit(&speaBuf[d+2], x * 0.3125f, memory_order_relaxed);
    }

    if (d > 2) {
        atomic_fetch_add_explicit(&speaBuf[d-3], x * 0.125f, memory_order_relaxed);
    }
    if (d < 49) {
        atomic_fetch_add_explicit(&speaBuf[d+3], x * 0.125f, memory_order_relaxed);
    }

    if (d > 3) {
        atomic_fetch_add_explicit(&speaBuf[d-4], x * 0.25f, memory_order_relaxed);
    }
    if (d < 48) {
        atomic_fetch_add_explicit(&speaBuf[d+4], x * 0.25f, memory_order_relaxed);
    }

    if (d > 4) {
        atomic_fetch_add_explicit(&speaBuf[d-5], x * 0.0625f, memory_order_relaxed);
    }
    if (d < 47) {
        atomic_fetch_add_explicit(&speaBuf[d+5], x * 0.0625f, memory_order_relaxed);
    }
}
