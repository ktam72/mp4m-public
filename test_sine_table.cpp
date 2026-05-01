#include <cstdio>
#include <cmath>
#include <cstdint>
#include "Vendor/opm/operator.h"

int main() {
    printf("OPM Sine Table Initialization Test\n\n");
    
    // Operator 作成（自動的に sine_table が初期化される）
    opm::Operator op;
    
    printf("Checking if sine table is initialized by creating an Operator...\n\n");
    
    // Operator の値を直接読めないので、代わりに以下のことを確認：
    // - LookupSine を間接的に呼び出す
    // - Calculate を呼び出して、sine_table が使用されているか確認
    
    // パラメータ設定
    op.SetKCKF(57, 32);  // A4
    op.SetMUL(1);
    op.SetTL(0);  // No attenuation
    op.SetAR(31);
    op.SetDR(15);
    op.SetSR(0);
    op.SetSL(0);
    op.SetRR(7);
    
    // Key on
    op.KeyOn();
    
    // テスト: 最初の 4 サンプルで sine_table が実際に使用されているか確認
    printf("First 4 raw operator outputs:\n");
    for (int i = 0; i < 4; i++) {
        int32_t out = op.Calculate(0, 0, 0);
        op.Prepare();
        printf("  Sample %d: %d (0x%08x)\n", i, (int)out, (unsigned)out);
    }
    
    printf("\nIf sine_table is ALL ZEROS (not initialized), output would be:\n");
    printf("  - 0 * (any value) = 0\n");
    printf("  - So all samples would be 0\n\n");
    
    printf("If sine_table is initialized correctly, output should be:\n");
    printf("  - Non-zero values representing a sine wave\n\n");
    
    // 確認: 多くのサンプルを生成して、非ゼロ出力の比率を確認
    int nonzero_count = 0;
    int max_out = 0;
    
    op.KeyOn();
    for (int i = 0; i < 44100; i++) {
        int32_t out = op.Calculate(0, 0, 0);
        op.Prepare();
        
        if (out != 0) nonzero_count++;
        if (out > max_out) max_out = out;
    }
    
    printf("Statistics over 44100 samples:\n");
    printf("  Non-zero outputs: %d (%.1f%%)\n", nonzero_count, (double)nonzero_count / 441.0);
    printf("  Max output: %d\n", max_out);
    
    if (nonzero_count > 40000) {
        printf("\n✓ Sine table appears to be initialized correctly!\n");
    } else if (nonzero_count == 0) {
        printf("\n⚠ ERROR: Sine table is all zeros (not initialized)!\n");
    } else {
        printf("\n? Unclear: sine_table may be partially initialized\n");
    }
    
    return 0;
}
