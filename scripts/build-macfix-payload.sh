#!/bin/bash
# Builds Resources/BO3MacFix.tar.gz, the payload MacFixInstaller extracts into
# the game folder. Takes upstream's release tar for the binary assets (cod2map,
# zone, Physics, natives) and swaps in our forked, rebranded dylib.
#
# Usage: scripts/build-macfix-payload.sh [path-to-upstream-release.tar]

set -euo pipefail

ROOT="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
SRC="$ROOT/vendor/BO3MacFix-src"
STAGING="$ROOT/.macfix-staging"
OUTPUT="$ROOT/Resources/BO3MacFix.tar.gz"

BASE_TAR="${1:-$SRC/BO3MacFix-upstream.tar}"

if [ ! -f "$BASE_TAR" ]; then
    echo "error: upstream release tar not found at $BASE_TAR" >&2
    echo "Pass one as an argument, or drop it at $SRC/BO3MacFix-upstream.tar" >&2
    echo "Releases: https://github.com/InvoxiPlayGames/BO3MacFix/releases" >&2
    exit 1
fi

echo "==> Building forked dylib"
make -C "$SRC" clean >/dev/null
make -C "$SRC"

echo "==> Staging from $(basename "$BASE_TAR")"
rm -rf "$STAGING"
mkdir -p "$STAGING"
tar xf "$BASE_TAR" -C "$STAGING"

if [ ! -d "$STAGING/BO3MacFix" ]; then
    echo "error: base tar has no BO3MacFix/ at its root" >&2
    exit 1
fi

echo "==> Swapping in forked dylib"
cp "$SRC/BO3MacFix.dylib" "$STAGING/BO3MacFix/BO3MacFix.dylib"

# Upstream's Wine prefix is generated on first run and is machine-specific.
rm -rf "$STAGING/BO3MacFix/pfx"

chmod 0644 "$STAGING/BO3MacFix/BO3MacFix.dylib"
chmod 0755 "$STAGING/BO3MacFix/Install_BO3MacFix" "$STAGING/BO3MacFix/AppBundleExe"

# Notarization unpacks this tarball inside the app and rejects every unsigned
# binary it finds, upstream's included. Hardened runtime applies only to these
# processes; the game is launched separately and stays unhardened, so the
# DYLD_INSERT_LIBRARIES injection still works.
echo "==> Signing payload binaries"
SIGN_ID="Developer ID Application: Max Awad (J497DX6ZF8)"
for binary in BO3MacFix.dylib Install_BO3MacFix AppBundleExe; do
    codesign --force --timestamp --options runtime \
        --sign "$SIGN_ID" "$STAGING/BO3MacFix/$binary"
done

echo "==> Writing $OUTPUT"
mkdir -p "$ROOT/Resources"
# No AppleDouble files: they break extraction onto non-APFS drives.
tar --no-mac-metadata --disable-copyfile --exclude='.DS_Store' \
    -czf "$OUTPUT" -C "$STAGING" BO3MacFix

rm -rf "$STAGING"

echo "==> Done: $(du -h "$OUTPUT" | cut -f1)"
strings -a "$SRC/BO3MacFix.dylib" | grep -m1 "^\[.*\] %s" || true
