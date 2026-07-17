#!/bin/zsh
set -euo pipefail

ROOT="${0:A:h:h}"
cd "$ROOT"
swift build -c release

APP="$ROOT/dist/Trans.app"
CONTENTS="$APP/Contents"
rm -rf "$APP"
mkdir -p "$CONTENTS/MacOS" "$CONTENTS/Resources"
cp "$ROOT/.build/release/Trans" "$CONTENTS/MacOS/Trans"
cp "$ROOT/Resources/Info.plist" "$CONTENTS/Info.plist"
cp "$ROOT/Resources/Trans.icns" "$CONTENTS/Resources/Trans.icns"
# Keep a stable designated requirement so macOS TCC permissions survive local rebuilds.
# A Developer ID certificate should replace ad-hoc signing for distribution.
codesign --force --deep --sign - \
  --requirements '=designated => identifier "com.trans.mac"' \
  "$APP"
echo "Built $APP"
