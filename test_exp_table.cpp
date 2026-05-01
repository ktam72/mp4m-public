#include <cstdio>
#include <cmath>
#include <cstdint>

int main() {
    printf("Exponential Attenuation Table Test\n");
    printf("Index | exp_table value | Linear (approx)\n");
    printf("------|-----------------|----------------\n");
    
    for (int i = 0; i < 256; i += 16) {
        double atten_db = -i * 0.75;
        double atten_linear = pow(10.0, atten_db / 20.0);
        int32_t exp_table_val = (int32_t)(atten_linear * 65536.0);
        
        printf("%3d   | %15d | %.6f (-%gdB)\n", i, exp_table_val, atten_linear, -atten_db);
    }
    
    printf("\n");
    printf("For sine = 32767 (max):\n");
    printf("  - exp_table[0] = 65536: output = 32767 * 65536 >> 16 = 32767 (max)\n");
    printf("  - exp_table[127] = ~327: output = 32767 * 327 >> 16 = 164 (very quiet)\n");
    printf("  - exp_table[255] = ~1: output ≈ 0 (silent)\n");
    
    return 0;
}
