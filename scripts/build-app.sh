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
# Swift Package Manager emits localized resources as a resource bundle next
# to the executable. Embed it in the app so localization also works for the
# signed distribution build (not only when running from .build).
for resourceBundle in "$ROOT"/.build/release/*.bundle; do
  [[ -d "$resourceBundle" ]] || continue
  cp -R "$resourceBundle" "$CONTENTS/Resources/"
  # SwiftUI's default Text/Label/Button localization resolves Localizable.strings
  # from the app's main bundle. Keep the package bundle for Bundle.module users,
  # and also expose each locale at the app resource root for those controls.
  for localization in "$resourceBundle"/*.lproj; do
    [[ -d "$localization" ]] || continue
    cp -R "$localization" "$CONTENTS/Resources/"
  done
done
# Keep a stable designated requirement so macOS TCC permissions survive local rebuilds.
# A Developer ID certificate should replace ad-hoc signing for distribution.
codesign --force --deep --sign - \
  --requirements '=designated => identifier "com.trans.mac"' \
  "$APP"
echo "Built $APP"
