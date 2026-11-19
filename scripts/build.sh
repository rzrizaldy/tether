#!/bin/zsh
# Builds Tether.app (Apple silicon + Intel).
#   ./scripts/build.sh            build into build/
#   ./scripts/build.sh --install  build, copy to /Applications (or ~/Applications) and open
#   ./scripts/build.sh --zip      build and write build/Tether.zip + .sha256 for a release
set -euo pipefail
cd "${0:A:h}/.."

APP=build/Tether.app
rm -rf build && mkdir -p "$APP/Contents/MacOS" "$APP/Contents/Resources"

for arch in arm64 x86_64; do
  swiftc -O -swift-version 5 -parse-as-library -import-objc-header Sources/Private.h \
    -target "$arch-apple-macos13.0" \
    -framework AppKit -framework IOKit -framework ServiceManagement \
    Sources/*.swift -o "build/Tether-$arch"
done
lipo -create build/Tether-arm64 build/Tether-x86_64 -output "$APP/Contents/MacOS/Tether"
rm build/Tether-arm64 build/Tether-x86_64

cp Resources/Info.plist "$APP/Contents/Info.plist"
cp Resources/AppIcon.icns "$APP/Contents/Resources/"
codesign --force --sign - "$APP"
echo "Built → $APP"

case "${1:-}" in
  --install)
    DEST=/Applications
    [[ -w $DEST ]] || { DEST=~/Applications; mkdir -p "$DEST"; }
    pkill -x Tether 2>/dev/null || true
    rm -rf "$DEST/Tether.app" && cp -R "$APP" "$DEST/"
    open "$DEST/Tether.app"
    echo "Installed → $DEST/Tether.app"
    ;;
  --zip)
    (cd build && ditto -c -k --keepParent Tether.app Tether.zip && shasum -a 256 Tether.zip > Tether.zip.sha256)
    cat build/Tether.zip.sha256
    ;;
esac
