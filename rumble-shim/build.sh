#!/bin/bash
# The game is an x86_64 Rosetta binary, so the shim has to match it. The test
# tool is built native so it can run without Rosetta.
set -euo pipefail
cd "$(dirname "$0")"

FRAMEWORKS="-framework AudioToolbox -framework CoreAudio -framework ForceFeedback -framework IOKit -framework CoreFoundation -lz"

echo "building shim (x86_64)..."
clang -arch x86_64 -dynamiclib -O2 -Wall \
    -o libdualsense_rumble.dylib dualsense_rumble.c $FRAMEWORKS

echo "building rumbletest (native)..."
clang -DDS_TEST_MAIN -O2 -Wall \
    -o rumbletest dualsense_rumble.c $FRAMEWORKS

# Notarization walks into Resources and rejects an ad-hoc signature, so prefer
# the Developer ID when it is on this machine. Ad-hoc is enough to run locally.
SIGN_ID="Developer ID Application: Max Awad (J497DX6ZF8)"
if security find-identity -v -p codesigning | grep -qF "$SIGN_ID"; then
    codesign -f -s "$SIGN_ID" --timestamp --options runtime libdualsense_rumble.dylib
else
    codesign -f -s - libdualsense_rumble.dylib
fi

echo
file libdualsense_rumble.dylib
file rumbletest

# GameLauncher injects <bo3Root>/BO3MacFix/DualSenseRumble.dylib when present.
if [ "${1:-}" = "install" ]; then
    DEST="/Volumes/Games/SteamLibrary/steamapps/common/Call of Duty Black Ops III/BO3MacFix"
    if [ -d "$DEST" ]; then
        # Staged then moved: overwriting in place has handed dyld a half
        # written file, which it reports as a code signature that does not
        # cover the whole file.
        cp libdualsense_rumble.dylib "$DEST/.DualSenseRumble.dylib.new"
        xattr -c "$DEST/.DualSenseRumble.dylib.new" 2>/dev/null || true
        mv -f "$DEST/.DualSenseRumble.dylib.new" "$DEST/DualSenseRumble.dylib"
        echo "installed -> $DEST/DualSenseRumble.dylib"
    else
        echo "game not mounted, skipped install" >&2
    fi
fi
