#!/bin/bash
# Builds NoteTune.app (standalone) with an embedded AUv3 effect extension. No Xcode project needed.
set -euo pipefail
cd "$(dirname "$0")"
OUT=build; rm -rf $OUT; mkdir -p $OUT
APP=$OUT/NoteTune.app
EXT=$APP/Contents/PlugIns/NoteTuneAU.appex
mkdir -p $APP/Contents/MacOS $EXT/Contents/MacOS
ARCH=$(uname -m)
TARGET=$ARCH-apple-macos13.0

echo "== compile app"
swiftc -O -parse-as-library -target $TARGET -module-name NoteTune \
  Shared/*.swift App/*.swift -o $APP/Contents/MacOS/NoteTune 2>&1 | tee $OUT/app-build.log

echo "== compile AUv3 extension"
swiftc -O -parse-as-library -application-extension -target $TARGET -module-name NoteTuneAU \
  Shared/*.swift AU/*.swift \
  -Xlinker -e -Xlinker _NSExtensionMain \
  -framework AudioToolbox -framework CoreAudioKit -framework AVFoundation \
  -o $EXT/Contents/MacOS/NoteTuneAU 2>&1 | tee $OUT/ext-build.log

cat > $APP/Contents/Info.plist <<'PL'
<?xml version="1.0" encoding="UTF-8"?>
<!DOCTYPE plist PUBLIC "-//Apple//DTD PLIST 1.0//EN" "http://www.apple.com/DTDs/PropertyList-1.0.dtd">
<plist version="1.0"><dict>
<key>CFBundleName</key><string>NoteTune</string>
<key>CFBundleDisplayName</key><string>NoteTune</string>
<key>CFBundleIdentifier</key><string>com.openindependence.notetune</string>
<key>CFBundleExecutable</key><string>NoteTune</string>
<key>CFBundlePackageType</key><string>APPL</string>
<key>CFBundleShortVersionString</key><string>0.2</string>
<key>CFBundleVersion</key><string>2</string>
<key>LSMinimumSystemVersion</key><string>13.0</string>
<key>NSPrincipalClass</key><string>NSApplication</string>
<key>NSHighResolutionCapable</key><true/>
</dict></plist>
PL

cat > $EXT/Contents/Info.plist <<'PL'
<?xml version="1.0" encoding="UTF-8"?>
<!DOCTYPE plist PUBLIC "-//Apple//DTD PLIST 1.0//EN" "http://www.apple.com/DTDs/PropertyList-1.0.dtd">
<plist version="1.0"><dict>
<key>CFBundleName</key><string>NoteTuneAU</string>
<key>CFBundleDisplayName</key><string>NoteTune</string>
<key>CFBundleIdentifier</key><string>com.openindependence.notetune.au</string>
<key>CFBundleExecutable</key><string>NoteTuneAU</string>
<key>CFBundlePackageType</key><string>XPC!</string>
<key>CFBundleShortVersionString</key><string>0.2</string>
<key>CFBundleVersion</key><string>2</string>
<key>LSMinimumSystemVersion</key><string>13.0</string>
<key>NSExtension</key>
<dict>
  <key>NSExtensionPointIdentifier</key><string>com.apple.AudioUnit-UI</string>
  <key>NSExtensionPrincipalClass</key><string>NoteTuneAUViewController</string>
  <key>NSExtensionAttributes</key>
  <dict>
    <key>AudioComponents</key>
    <array><dict>
      <key>name</key><string>Open Independence: NoteTune</string>
      <key>description</key><string>Accessible note by note pitch editor</string>
      <key>manufacturer</key><string>OInd</string>
      <key>subtype</key><string>ntun</string>
      <key>type</key><string>aufx</string>
      <key>version</key><integer>2</integer>
      <key>sandboxSafe</key><true/>
      <key>tags</key><array><string>Effects</string></array>
    </dict></array>
  </dict>
</dict>
</dict></plist>
PL

cat > $OUT/ext.entitlements <<'PL'
<?xml version="1.0" encoding="UTF-8"?>
<!DOCTYPE plist PUBLIC "-//Apple//DTD PLIST 1.0//EN" "http://www.apple.com/DTDs/PropertyList-1.0.dtd">
<plist version="1.0"><dict>
<key>com.apple.security.app-sandbox</key><true/>
</dict></plist>
PL

echo "== sign (ad-hoc)"
codesign --force --sign - --entitlements $OUT/ext.entitlements $EXT
codesign --force --sign - $APP
codesign --verify --deep --strict --verbose=2 $APP
echo "== validate registration (informational)"
pluginkit -a $EXT || true
(auval -v aufx ntun OInd 2>&1 | tail -40) || true
ditto -c -k --keepParent $APP $OUT/NoteTune-mac.zip
ls -la $OUT
