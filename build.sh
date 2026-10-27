#!/bin/zsh
set -euo pipefail
cd "${0:A:h}"
DIST_APP_PATH="$PWD/dist/notchplayer.app"
zsh Tools/prepare-sparkle.sh
# Desktop sync can add Finder metadata between cleanup and signing; sign entirely outside it.
BUILD_STAGE=$(mktemp -d "${TMPDIR:-/tmp/}notchplayer-build.XXXXXX")
trap 'rm -rf "$BUILD_STAGE"' EXIT
APP_PATH="$BUILD_STAGE/notchplayer.app"
mkdir -p "$APP_PATH/Contents/MacOS"
ICON_DEVELOPER_DIR="${DEVELOPER_DIR:-$(xcode-select -p)}"
if [[ ! -x "$ICON_DEVELOPER_DIR/usr/bin/actool" && -x /Applications/Xcode.app/Contents/Developer/usr/bin/actool ]]; then
  ICON_DEVELOPER_DIR=/Applications/Xcode.app/Contents/Developer
fi
if [[ ! -x "$ICON_DEVELOPER_DIR/usr/bin/actool" ]]; then
  print -u2 "Building the native Liquid Glass app icon requires Xcode with Icon Composer support."
  exit 1
fi
mkdir -p "$BUILD_STAGE/Icon"
DEVELOPER_DIR="$ICON_DEVELOPER_DIR" "$ICON_DEVELOPER_DIR/usr/bin/actool" Resources/AppIcon.icon --compile "$BUILD_STAGE/Icon" --output-format human-readable-text --notices --warnings --errors --output-partial-info-plist "$BUILD_STAGE/Icon/partial.plist" --app-icon AppIcon --include-all-app-icons --enable-on-demand-resources NO --development-region en --target-device mac --minimum-deployment-target 14.0 --platform macosx
for ARCH in arm64 x86_64; do
  xcrun swiftc -swift-version 5 -O -parse-as-library Sources/*.swift -o "$BUILD_STAGE/notchplayer-$ARCH" -F .build/Sparkle -framework Sparkle -Xlinker -rpath -Xlinker @executable_path/../Frameworks -framework AppKit -framework ServiceManagement -framework Accelerate -framework CoreAudio -framework AudioToolbox -framework SwiftUI -framework UniformTypeIdentifiers -target "$ARCH-apple-macosx14.0"
done
xcrun lipo -create "$BUILD_STAGE/notchplayer-arm64" "$BUILD_STAGE/notchplayer-x86_64" -output "$APP_PATH/Contents/MacOS/notchplayer"
/usr/libexec/PlistBuddy -c 'Clear dict' "$APP_PATH/Contents/Info.plist"
/usr/libexec/PlistBuddy -c 'Add :CFBundleExecutable string notchplayer' -c 'Add :CFBundleIdentifier string local.nooklab.prototype' -c 'Add :CFBundleName string notchplayer' -c 'Add :CFBundleDisplayName string notchplayer' -c 'Add :CFBundlePackageType string APPL' -c 'Add :CFBundleShortVersionString string 0.2.75' -c 'Add :CFBundleVersion string 75' -c 'Add :CFBundleIconFile string AppIcon' -c 'Add :NSAudioCaptureUsageDescription string 读取当前音乐播放器的音频以显示实时高低频波形；仅在内存分析，不保存或上传音频。' -c 'Add :LSMinimumSystemVersion string 14.0' -c 'Add :LSUIElement bool true' -c 'Add :NSHighResolutionCapable bool true' "$APP_PATH/Contents/Info.plist"
/usr/libexec/PlistBuddy -c 'Add :SUFeedURL string https://github.com/thorpjia-cloud/notchplayer/releases/latest/download/appcast.xml' -c "Add :SUPublicEDKey string $(cat Resources/UpdatePublicKey.txt)" -c 'Add :SUEnableAutomaticChecks bool true' -c 'Add :SUAutomaticallyUpdate bool false' -c 'Add :SUScheduledCheckInterval integer 86400' -c 'Add :SUVerifyUpdateBeforeExtraction bool true' -c 'Add :SURequireSignedFeed bool true' "$APP_PATH/Contents/Info.plist"
mkdir -p "$APP_PATH/Contents/Frameworks"
ditto --norsrc .build/Sparkle/Sparkle.framework "$APP_PATH/Contents/Frameworks/Sparkle.framework"
mkdir -p "$APP_PATH/Contents/Resources"
cp "$BUILD_STAGE/Icon/AppIcon.icns" "$BUILD_STAGE/Icon/Assets.car" "$APP_PATH/Contents/Resources/"
/usr/libexec/PlistBuddy -c 'Add :CFBundleIconName string AppIcon' "$APP_PATH/Contents/Info.plist"
xcrun clang -dynamiclib -fobjc-arc -fvisibility=default -arch arm64 -arch x86_64 -mmacosx-version-min=14.0 -I Vendor/mediaremote-adapter/include -I Vendor/mediaremote-adapter/src Vendor/mediaremote-adapter/src/adapter/*.m Vendor/mediaremote-adapter/src/private/*.m Vendor/mediaremote-adapter/src/utility/*.m -framework Foundation -framework AppKit -framework UniformTypeIdentifiers -o MediaRemoteAdapter.framework/MediaRemoteAdapter
ditto --norsrc MediaRemoteAdapter.framework "$APP_PATH/Contents/Resources/MediaRemoteAdapter.framework"
cp Vendor/mediaremote-adapter/bin/mediaremote-adapter.pl "$APP_PATH/Contents/Resources/"
cp 使用说明.txt NOTICE.md "$APP_PATH/Contents/Resources/"
cp Vendor/mediaremote-adapter/LICENSE "$APP_PATH/Contents/Resources/MediaRemoteAdapter-LICENSE.txt"
cp Vendor/Sparkle/LICENSE "$APP_PATH/Contents/Resources/Sparkle-LICENSE.txt"
xattr -dr com.apple.FinderInfo "$APP_PATH" 2>/dev/null || true
xattr -dr com.apple.ResourceFork "$APP_PATH" 2>/dev/null || true
codesign --force --deep --sign - "$APP_PATH"
codesign --verify --deep --strict "$APP_PATH"
ditto --norsrc "$APP_PATH" "$DIST_APP_PATH"
print "Built: $DIST_APP_PATH"
