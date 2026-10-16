#!/usr/bin/env bash
set -euo pipefail

project_dir="$(cd "$(dirname "$0")/.." && pwd)"
app_dir="$project_dir/.build/distribution/Yootube.app"
dmg="$project_dir/dist/Yootube.dmg"
generator="$project_dir/.build/artifacts/sparkle/Sparkle/bin/generate_appcast"

[[ -f "$dmg" && -x "$generator" && -d "$app_dir" ]] || {
    echo "Build dist/Yootube.dmg before generating the appcast." >&2
    exit 1
}
codesign --verify --deep --strict "$app_dir"
codesign -dv "$app_dir" 2>&1 | grep -q 'Authority=Developer ID Application' || {
    echo "A Developer ID Application signature is required for a public update." >&2
    exit 1
}
xcrun stapler validate "$dmg" >/dev/null || {
    echo "Notarize and staple the DMG before publishing an update." >&2
    exit 1
}

version="$(/usr/libexec/PlistBuddy -c 'Print CFBundleShortVersionString' "$app_dir/Contents/Info.plist")"
staging="$(mktemp -d)"
trap 'rm -rf "$staging"' EXIT
cp "$dmg" "$staging/Yootube.dmg"
cp "$project_dir/appcast.xml" "$staging/appcast.xml"

"$generator" \
    --maximum-deltas 0 \
    --download-url-prefix "https://github.com/nicing/Yootube/releases/download/v$version/" \
    --link "https://github.com/nicing/Yootube/releases" \
    -o "$staging/appcast.xml" "$staging"
cp "$staging/appcast.xml" "$project_dir/appcast.xml"
echo "Updated appcast.xml for v$version. Commit and push it after uploading the matching DMG Release."
