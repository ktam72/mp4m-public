#!/bin/bash
# LZX比較テストのコンパイルと実行スクリプト

set -e

PROJ_DIR="/Users/ktam/Documents/apps/MP4M"
MDX_FILE="${1:-/Users/ktam/Downloads/MDX/Arsys/Knight_Arms/KNA03A.MDX}"
OUTPUT_DIR="${PROJ_DIR}/build_test"
mkdir -p "${OUTPUT_DIR}"

echo "=== Compiling LZX Compare Test ==="
echo "MDX File: ${MDX_FILE}"

# コンパイル
clang++ -std=c++17 -Wall -Wextra \
  -I"${PROJ_DIR}" \
  -I"${PROJ_DIR}/Vendor" \
  -I"${PROJ_DIR}/Vendor/lzx" \
  "${PROJ_DIR}/test_lzx_compare.cpp" \
  "${PROJ_DIR}/Vendor/lzx/lzx.cpp" \
  "${PROJ_DIR}/Vendor/lzx/lzx042.c" \
  -o "${OUTPUT_DIR}/test_lzx_compare"

echo "Compile successful: ${OUTPUT_DIR}/test_lzx_compare"

# 実行
echo ""
echo "=== Running LZX Compare Test ==="
"${OUTPUT_DIR}/test_lzx_compare" "${MDX_FILE}"

echo ""
echo "=== Test Complete ==="
