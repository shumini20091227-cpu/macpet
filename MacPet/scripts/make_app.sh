#!/bin/zsh
set -euo pipefail

ROOT="$(cd "$(dirname "$0")/.." && pwd)"
cd "$ROOT"

swift build -c release "$@"
BIN_DIR="$(swift build -c release "$@" --show-bin-path)"
BIN="$BIN_DIR/MacPet"
APP="${MACPET_APP_OUTPUT:-$ROOT/MacPet.app}"

rm -rf "$APP"
mkdir -p "$APP/Contents/MacOS" "$APP/Contents/Resources"
cp "$ROOT/AppBundle/Info.plist" "$APP/Contents/Info.plist"
"$ROOT/scripts/make_icon.sh"
cp "$ROOT/AppBundle/MacPet.icns" "$APP/Contents/Resources/MacPet.icns"
cp "$BIN" "$APP/Contents/MacOS/MacPet"
chmod +x "$APP/Contents/MacOS/MacPet"
cp -R "$ROOT/Sources/MacPet/Resources/." "$APP/Contents/Resources/"
cp -R "$BIN_DIR/MacPet_MacPet.bundle" "$APP/Contents/Resources/"
codesign --force --sign "${CODE_SIGN_IDENTITY:--}" "$APP"

echo "Built $APP"

