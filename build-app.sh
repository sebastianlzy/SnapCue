#!/bin/sh
set -eu
cd "$(dirname "$0")"
swift build -c release
bin=$(swift build -c release --show-bin-path)
bundle=dist/SnapCue.app
mkdir -p "$bundle/Contents/MacOS"
cp "$bin/SnapCue" "$bundle/Contents/MacOS/SnapCue"
cat > "$bundle/Contents/Info.plist" <<'PLIST'
<?xml version="1.0" encoding="UTF-8"?>
<!DOCTYPE plist PUBLIC "-//Apple//DTD PLIST 1.0//EN" "http://www.apple.com/DTDs/PropertyList-1.0.dtd">
<plist version="1.0">
<dict>
    <key>CFBundleExecutable</key><string>SnapCue</string>
    <key>CFBundleIdentifier</key><string>com.sebastianlzy.snapcue</string>
    <key>CFBundleName</key><string>SnapCue</string>
    <key>CFBundlePackageType</key><string>APPL</string>
    <key>CFBundleShortVersionString</key><string>0.1.0</string>
    <key>CFBundleVersion</key><string>1</string>
    <key>LSMinimumSystemVersion</key><string>14.0</string>
    <key>LSUIElement</key><true/>
</dict>
</plist>
PLIST
codesign --force --sign - "$bundle"
printf '%s\n' "$bundle"
