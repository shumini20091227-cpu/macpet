#!/bin/zsh
set -euo pipefail

ROOT="$(cd "$(dirname "$0")/.." && pwd)"
cd "$ROOT"

swift build -c release
BIN=".build/release/MacPet"
APP="$ROOT/MacPet.app"

rm -rf "$APP"
mkdir -p "$APP/Contents/MacOS" "$APP/Contents/Resources"
cp "$ROOT/AppBundle/Info.plist" "$APP/Contents/Info.plist"
cp "$BIN" "$APP/Contents/MacOS/MacPet"
chmod +x "$APP/Contents/MacOS/MacPet"
cp "$ROOT/Sources/MacPet/Resources/pet_character.png" "$APP/Contents/Resources/pet_character.png"
cp "$ROOT/Sources/MacPet/Resources/pet_study.png" "$APP/Contents/Resources/pet_study.png"

echo "Built $APP"
