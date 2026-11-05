#!/bin/bash
# Build and self-test the native desktop pet; --package also creates a DMG.
set -euo pipefail
cd "$(dirname "$0")"
APP_NAME="陈震桌宠"
EXECUTABLE="ChenzhenPet"
FINAL_BUNDLE="build/$APP_NAME.app"
# Sign before using the .app suffix: synced filesystems may attach Finder metadata.
BUNDLE="tmp/app-bundle"
VERSION="1.3.4"
PACKAGE=0
SELF_TEST=1
for arg in "$@"; do
    case "$arg" in
        --package) PACKAGE=1 ;;
        --no-self-test) SELF_TEST=0 ;;
        *) printf '未知参数：%s\n' "$arg" >&2; exit 2 ;;
    esac
done
[[ "$(uname -s)" == Darwin && "$(uname -m)" == arm64 ]] || { echo '需要 Apple Silicon Mac。' >&2; exit 1; }
command -v swiftc >/dev/null || { echo '需要 Xcode Command Line Tools 中的 swiftc。' >&2; exit 1; }
[[ -f Assets/face.png && -f Assets/clips.json && -f Assets/AppIcon.icns ]] || { echo '缺少人物素材或台词配置。' >&2; exit 1; }
rm -rf "$BUNDLE"
mkdir -p "$BUNDLE/Contents/MacOS" "$BUNDLE/Contents/Resources" verification build
swiftc -O -target arm64-apple-macosx14.0 -framework AppKit -framework AVFoundation \
    Sources/*.swift -o "$BUNDLE/Contents/MacOS/$EXECUTABLE"
# Copy only runtime assets, keeping download tools and source videos outside the App.
rm -rf "$BUNDLE/Contents/Resources/Clips"
cp -R Assets/Clips "$BUNDLE/Contents/Resources/"
cp Assets/face.png Assets/clips.json Assets/caption-bubble.png Assets/AppIcon.icns "$BUNDLE/Contents/Resources/"
cp Assets/actions.json Assets/portraits.json "$BUNDLE/Contents/Resources/"
cp -R Assets/Portraits "$BUNDLE/Contents/Resources/"
cp -R Assets/Actions "$BUNDLE/Contents/Resources/"
cp -R licenses "$BUNDLE/Contents/Resources/"
cp LICENSE ASSETS_LICENSE.md CREDITS.txt 使用说明.txt "$BUNDLE/Contents/Resources/"
cp materials/sources.json "$BUNDLE/Contents/Resources/素材来源.json"
cat > "$BUNDLE/Contents/Info.plist" <<PLIST
<?xml version="1.0" encoding="UTF-8"?>
<!DOCTYPE plist PUBLIC "-//Apple//DTD PLIST 1.0//EN" "http://www.apple.com/DTDs/PropertyList-1.0.dtd">
<plist version="1.0"><dict>
<key>CFBundleExecutable</key><string>$EXECUTABLE</string>
<key>CFBundleIdentifier</key><string>local.chenzhen.desktop-pet</string>
<key>CFBundleName</key><string>$APP_NAME</string>
<key>CFBundleDisplayName</key><string>$APP_NAME</string>
<key>CFBundlePackageType</key><string>APPL</string>
<key>CFBundleShortVersionString</key><string>$VERSION</string>
<key>CFBundleVersion</key><string>13</string>
<key>LSMinimumSystemVersion</key><string>14.0</string>
<key>LSUIElement</key><true/>
<key>NSHighResolutionCapable</key><true/>
<key>CFBundleIconFile</key><string>AppIcon</string>
</dict></plist>
PLIST
# Desktop/Finder can attach metadata while assembling a bundle; it is not a resource.
xattr -cr "$BUNDLE"
xattr -d com.apple.FinderInfo "$BUNDLE" 2>/dev/null || true
codesign --force --sign - "$BUNDLE"
codesign --verify --deep --strict "$BUNDLE"
rm -rf "$FINAL_BUNDLE"
mv "$BUNDLE" "$FINAL_BUNDLE"
BUNDLE="$FINAL_BUNDLE"
# The complete staged tree was verified before renaming. A synced filesystem may
# attach metadata after the rename; the distribution tree is verified on its HFS+ image.
xattr -c "$BUNDLE/Contents/MacOS/$EXECUTABLE"
if [[ "$SELF_TEST" == 1 ]]; then
    "$BUNDLE/Contents/MacOS/$EXECUTABLE" --self-test --latency-report "$PWD/tmp/audio-scheduling-build.json" --snapshot "$PWD/verification/self-test.png" | tee verification/self-test.log
fi
if [[ "$PACKAGE" == 1 ]]; then
    mkdir -p dist tmp
    # Assemble on a mounted image so a synced filesystem cannot reattach package metadata.
    STAGING="tmp/package.dmg"
    MOUNT="/Volumes/ChenzhenPet-package-$$"
    trap 'hdiutil detach -quiet "$MOUNT" 2>/dev/null || true; rm -f "$STAGING"' EXIT
    hdiutil create -quiet -size 64m -fs HFS+ -volname "$APP_NAME" -ov "$STAGING"
    hdiutil attach -quiet -nobrowse -mountpoint "$MOUNT" "$STAGING"
    ditto --norsrc --noextattr "$BUNDLE" "$MOUNT/$APP_NAME.app"
    ln -s /Applications "$MOUNT/Applications"
    codesign --verify --deep --strict "$MOUNT/$APP_NAME.app"
    hdiutil detach -quiet "$MOUNT"
    hdiutil convert -quiet "$STAGING" -ov -format UDZO -o "dist/ChenzhenPet-$VERSION.dmg"
    (cd dist && shasum -a 256 "ChenzhenPet-$VERSION.dmg" > "ChenzhenPet-$VERSION.sha256")
fi
printf '完成：%s\n' "$PWD/$BUNDLE"
