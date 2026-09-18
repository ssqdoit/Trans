#!/bin/zsh
set -euo pipefail

ROOT="${0:A:h:h}"
cd "$ROOT"
swift build -c release "$@"
BIN_DIR="$(swift build -c release "$@" --show-bin-path)"

APP="$ROOT/dist/Trans.app"
CONTENTS="$APP/Contents"
rm -rf "$APP"
mkdir -p "$CONTENTS/MacOS" "$CONTENTS/Resources"
cp "$BIN_DIR/Trans" "$CONTENTS/MacOS/Trans"
cp "$ROOT/Resources/Info.plist" "$CONTENTS/Info.plist"
cp "$ROOT/Resources/Trans.icns" "$CONTENTS/Resources/Trans.icns"
if [[ -n "${TRANS_VERSION:-}" ]]; then
  /usr/libexec/PlistBuddy -c "Set :CFBundleShortVersionString $TRANS_VERSION" "$CONTENTS/Info.plist"
fi
if [[ -n "${TRANS_BUILD_NUMBER:-}" ]]; then
  /usr/libexec/PlistBuddy -c "Set :CFBundleVersion $TRANS_BUILD_NUMBER" "$CONTENTS/Info.plist"
fi
# Swift Package Manager emits localized resources as a resource bundle next
# to the executable. Embed it in the app so localization also works for the
# signed distribution build (not only when running from .build).
for resourceBundle in "$BIN_DIR"/*.bundle(N); do
  [[ -d "$resourceBundle" ]] || continue
  cp -R "$resourceBundle" "$CONTENTS/Resources/"
  # SwiftUI's default Text/Label/Button localization resolves Localizable.strings
  # from the app's main bundle. Keep the package bundle for Bundle.module users,
  # and also expose each locale at the app resource root for those controls.
  resourceDirectory="$resourceBundle"
  if [[ -d "$resourceBundle/Contents/Resources" ]]; then
    resourceDirectory="$resourceBundle/Contents/Resources"
  fi
  for localization in "$resourceDirectory"/*.lproj(N); do
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
