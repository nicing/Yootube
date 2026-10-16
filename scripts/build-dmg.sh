#!/usr/bin/env bash
set -euo pipefail

project_dir="$(cd "$(dirname "$0")/.." && pwd)"
build_dir="$project_dir/.build/distribution"
app_dir="$build_dir/Yootube.app"
dmg_root="$build_dir/dmg"
output_dir="$project_dir/dist"

cd "$project_dir"
swift build -c release

rm -rf "$build_dir" "$output_dir/Yootube.dmg"
mkdir -p "$app_dir/Contents/MacOS" "$app_dir/Contents/Resources" "$dmg_root" "$output_dir"
cp "$project_dir/.build/release/Yootube" "$app_dir/Contents/MacOS/Yootube"
cp -R "$project_dir/.build/release/Yootube_Yootube.bundle" "$app_dir/Contents/Resources/"
swift "$project_dir/scripts/create-icon.swift" "$build_dir/AppIcon.iconset"
iconutil -c icns "$build_dir/AppIcon.iconset" -o "$app_dir/Contents/Resources/AppIcon.icns"
"$project_dir/scripts/prepare-runtime.sh" "$app_dir/Contents/Resources/Runtime"

cat > "$app_dir/Contents/Info.plist" <<'PLIST'
<?xml version="1.0" encoding="UTF-8"?>
<!DOCTYPE plist PUBLIC "-//Apple//DTD PLIST 1.0//EN" "http://www.apple.com/DTDs/PropertyList-1.0.dtd">
<plist version="1.0">
<dict>
    <key>CFBundleDisplayName</key>
    <string>Yootube</string>
    <key>CFBundleExecutable</key>
    <string>Yootube</string>
    <key>CFBundleIdentifier</key>
    <string>com.local.yootube</string>
    <key>CFBundleInfoDictionaryVersion</key>
    <string>6.0</string>
    <key>CFBundleName</key>
    <string>Yootube</string>
    <key>CFBundleIconFile</key>
    <string>AppIcon</string>
    <key>CFBundlePackageType</key>
    <string>APPL</string>
    <key>CFBundleShortVersionString</key>
    <string>1.21.1</string>
    <key>CFBundleVersion</key>
    <string>123</string>
    <key>LSMinimumSystemVersion</key>
    <string>14.0</string>
    <key>NSHighResolutionCapable</key>
    <true/>
    <key>UTExportedTypeDeclarations</key>
    <array>
        <dict>
            <key>UTTypeConformsTo</key>
            <array>
                <string>public.json</string>
            </array>
            <key>UTTypeDescription</key>
            <string>Yootube Folder Drag Payload</string>
            <key>UTTypeIdentifier</key>
            <string>com.local.yootube.folder-drag-payload</string>
        </dict>
        <dict>
            <key>UTTypeConformsTo</key>
            <array>
                <string>public.json</string>
            </array>
            <key>UTTypeDescription</key>
            <string>Yootube Video Drag Payload</string>
            <key>UTTypeIdentifier</key>
            <string>com.local.yootube.video-drag-payload</string>
        </dict>
    </array>
    <key>NSAppTransportSecurity</key>
    <dict>
        <key>NSAllowsLocalNetworking</key>
        <true/>
    </dict>
</dict>
</plist>
PLIST

codesign --force --deep --sign - "$app_dir"
cp -R "$app_dir" "$dmg_root/Yootube.app"
ln -s /Applications "$dmg_root/Applications"

hdiutil create \
    -volname "Yootube" \
    -srcfolder "$dmg_root" \
    -ov \
    -format UDZO \
    "$output_dir/Yootube.dmg"

echo "Created $output_dir/Yootube.dmg"
