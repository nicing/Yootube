#!/usr/bin/env bash
set -euo pipefail

project_dir="$(cd "$(dirname "$0")/.." && pwd)"
build_dir="$project_dir/.build/distribution"
app_dir="$build_dir/Yootube.app"
dmg_root="$build_dir/dmg"
output_dir="$project_dir/dist"
version="${YOOTUBE_VERSION:-1.21.1}"
build_number="${YOOTUBE_BUILD_NUMBER:-123}"
signing_identity="${YOOTUBE_CODESIGN_IDENTITY:--}"

[[ "$version" =~ ^[0-9]+(\.[0-9]+)+$ ]] || { echo "Invalid YOOTUBE_VERSION" >&2; exit 1; }
[[ "$build_number" =~ ^[0-9]+$ ]] || { echo "Invalid YOOTUBE_BUILD_NUMBER" >&2; exit 1; }

cd "$project_dir"
swift build -c release

rm -rf "$build_dir" "$output_dir/Yootube.dmg"
mkdir -p "$app_dir/Contents/MacOS" "$app_dir/Contents/Resources" "$dmg_root" "$output_dir"
cp "$project_dir/.build/release/Yootube" "$app_dir/Contents/MacOS/Yootube"
cp -R "$project_dir/.build/release/Yootube_Yootube.bundle" "$app_dir/Contents/Resources/"
mkdir -p "$app_dir/Contents/Frameworks"
cp -R "$project_dir/.build/artifacts/sparkle/Sparkle/Sparkle.xcframework/macos-arm64_x86_64/Sparkle.framework" \
    "$app_dir/Contents/Frameworks/"
cp "$project_dir/.build/artifacts/sparkle/Sparkle/LICENSE" "$app_dir/Contents/Resources/Sparkle-LICENSE.txt"
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
    <key>SUFeedURL</key>
    <string>https://raw.githubusercontent.com/nicing/Yootube/main/appcast.xml</string>
    <key>SUPublicEDKey</key>
    <string>JdGZLxEqYLpA83Z8L/iBoeQ/2OcApHUgVbpzexh8Fs8=</string>
    <key>SUEnableAutomaticChecks</key>
    <true/>
    <key>SUAutomaticallyUpdate</key>
    <false/>
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

plutil -replace CFBundleShortVersionString -string "$version" "$app_dir/Contents/Info.plist"
plutil -replace CFBundleVersion -string "$build_number" "$app_dir/Contents/Info.plist"
if [[ "$signing_identity" == "-" ]]; then
    codesign --force --deep --sign - "$app_dir"
else
    codesign --force --deep --options runtime --timestamp --sign "$signing_identity" "$app_dir"
fi
cp -R "$app_dir" "$dmg_root/Yootube.app"
ln -s /Applications "$dmg_root/Applications"

hdiutil create \
    -volname "Yootube" \
    -srcfolder "$dmg_root" \
    -ov \
    -format UDZO \
    "$output_dir/Yootube.dmg"

echo "Created $output_dir/Yootube.dmg"
