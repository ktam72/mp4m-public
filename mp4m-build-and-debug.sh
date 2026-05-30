#!/bin/zsh
#
# MP4M Build + Debug Launcher
# ===========================
#
# Usage:
#   ./mp4m-build-and-debug.sh
#
# With ymfm debug logging (strongly recommended for KNA03.MDX etc. investigation):
#   MP4M_YMFM_DEBUG=1 ./mp4m-build-and-debug.sh
#
# With both normal + high-frequency logging (best for seeing the very first frames):
#   MP4M_YMFM_DEBUG=1 MP4M_YMFM_HIGHRES=1 ./mp4m-build-and-debug.sh
#
# This script forces the build output into ./build/DerivedData so the
# location of the built app is predictable and stays inside the project folder.
#

set -euo pipefail

cd "$(dirname "$0")"

echo "=== MP4M Build & Debug ==="
echo "Working directory: $(pwd)"

DERIVED_DATA_PATH="./build/DerivedData"
APP_BINARY="$DERIVED_DATA_PATH/Build/Products/Debug/MP4M.app/Contents/MacOS/MP4M"

echo ""
echo ">>> Building Debug version (output → $DERIVED_DATA_PATH) ..."

xcodebuild \
    -project MP4M.xcodeproj \
    -scheme MP4M \
    -configuration Debug \
    -derivedDataPath "$DERIVED_DATA_PATH" \
    build

if [ ! -f "$APP_BINARY" ]; then
    echo ""
    echo "Error: Could not find built app at:"
    echo "  $APP_BINARY"
    echo ""
    echo "Possible causes:"
    echo "  - Build succeeded but app location is different"
    echo "  - Scheme or target name has changed"
    echo ""
    echo "Try building once from Xcode GUI, then run this script again."
    exit 1
fi

# Prepare log file
TIMESTAMP=$(date +%Y%m%d_%H%M%S)
LOGFILE="mp4m_debug_${TIMESTAMP}.log"

echo ""
echo ">>> Launching app..."
echo "    Binary : $APP_BINARY"
echo "    Logfile: $LOGFILE"
echo ""
echo "    Tips:"
echo "    - Play the target song for 10-15 seconds, then quit the app (Cmd+Q)"
echo "    - For dense early logs (useful for debugging initial state issues):"
echo "        MP4M_YMFM_DEBUG=1 MP4M_YMFM_HIGHRES=1 ./mp4m-build-and-debug.sh"
echo ""
echo "    Press Ctrl+C to stop logging early."
echo ""

# Forward any environment variables (DEBUG + HIGHRES)
env "$@" "$APP_BINARY" 2>&1 | tee "$LOGFILE"

echo ""
echo "=== Done ==="
echo "Log saved to: $LOGFILE"
echo ""
echo "Next steps:"
echo "  - Search for [YMFM_CH], [YMFM_CH_INIT], [FMGEN_CH], [OPM_DEBUG] etc."
echo "  - The [YMFM_CH_INIT] / [FMGEN_CH_INIT] blocks right after load are useful for initial state comparison."