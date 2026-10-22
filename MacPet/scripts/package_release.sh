#!/bin/zsh
set -euo pipefail
ROOT="$(cd "$(dirname "$0")/.." && pwd)"
REPO="$(cd "$ROOT/.." && pwd)"
VERSION=$(/usr/libexec/PlistBuddy -c 'Print :CFBundleShortVersionString' "$ROOT/AppBundle/Info.plist")
DIST="$REPO/dist"
STAGE="$DIST/MacPet-$VERSION"
mkdir -p "$STAGE"
export MACPET_APP_OUTPUT="$STAGE/MacPet.app"
"$ROOT/scripts/make_app.sh" --arch arm64 --arch x86_64 "$@"
"$MACPET_APP_OUTPUT/Contents/MacOS/MacPet" --verify-release
codesign --verify --deep --strict "$MACPET_APP_OUTPUT"
ARCHS="$(lipo -archs "$MACPET_APP_OUTPUT/Contents/MacOS/MacPet")"
[[ " $ARCHS " == *" arm64 "* && " $ARCHS " == *" x86_64 "* ]]
cp "$REPO/docs/INSTALL.zh-CN.txt" "$STAGE/安装说明.txt"
cp "$REPO/LICENSE" "$STAGE/LICENSE.txt"
cp "$REPO/CHANGELOG.md" "$STAGE/更新日志.md"
ln -sfn /Applications "$STAGE/Applications"
ditto -c -k --sequesterRsrc --keepParent "$STAGE" "$DIST/MacPet-$VERSION-universal.zip"
cd "$DIST"
shasum -a 256 "MacPet-$VERSION-universal.zip" > SHA256SUMS.txt
echo "Release: $DIST/MacPet-$VERSION-universal.zip"
