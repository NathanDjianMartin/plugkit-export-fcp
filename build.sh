#!/bin/bash
# Build PlugKit Export.app (host app + Final Cut Workflow Extension) with Command Line Tools only.
set -euo pipefail
cd "$(dirname "$0")"
SDK=/Library/Developer/SDKs/WorkflowExtensionSDK.sdk
OUT="build/PlugKit Export.app"
APPEX="$OUT/Contents/PlugIns/PlugKitExportExt.appex"
rm -rf build && mkdir -p "$OUT/Contents/MacOS" "$OUT/Contents/Resources" "$APPEX/Contents/MacOS"

swiftc -O -target arm64-apple-macos26.0 -parse-as-library -module-name PlugKitExport \
  -o "$OUT/Contents/MacOS/PlugKitExport" App/*.swift Shared/*.swift
cp App.plist "$OUT/Contents/Info.plist"
cp Resources/PlugKit.fcpxdest "$OUT/Contents/Resources/"

swiftc -O -target arm64-apple-macos26.0 -application-extension -parse-as-library -module-name PlugKitExportExt \
  -F "$SDK/Library/Frameworks" -L "$SDK/usr/lib" -lProExtension \
  -Xlinker -e -Xlinker _ProExtensionMain \
  -Xlinker -rpath -Xlinker "/Applications/Final Cut Pro.app/Contents/Frameworks" \
  -framework ProExtensionHost -import-objc-header Bridging-Header.h -Xcc -I"$SDK/usr/include" \
  -o "$APPEX/Contents/MacOS/PlugKitExportExt" Extension/*.swift Shared/*.swift
cp Extension.plist "$APPEX/Contents/Info.plist"

IDENTITY="${IDENTITY:--}"
codesign --force --sign "$IDENTITY" --entitlements Extension.entitlements "$APPEX"
codesign --force --sign "$IDENTITY" "$OUT"
echo "OK -> $OUT"
