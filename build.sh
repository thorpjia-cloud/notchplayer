#!/bin/zsh
set -euo pipefail
cd "${0:A:h}"
APP_PATH="$PWD/dist/notchplayer.app"
mkdir -p "$APP_PATH/Contents/MacOS"
# Keep compiler intermediates outside Desktop sync folders; release packages use a clean signing stage.
BUILD_STAGE=$(mktemp -d "${TMPDIR:-/tmp/}notchplayer-build.XXXXXX")
trap 'rm -rf "$BUILD_STAGE"' EXIT
for ARCH in arm64 x86_64; do
  xcrun swiftc -swift-version 5 -O -parse-as-library Sources/*.swift -o "$BUILD_STAGE/notchplayer-$ARCH" -framework AppKit -framework Accelerate -framework CoreAudio -framework AudioToolbox -framework SwiftUI -framework UniformTypeIdentifiers -target "$ARCH-apple-macosx14.0"
done
xcrun lipo -create "$BUILD_STAGE/notchplayer-arm64" "$BUILD_STAGE/notchplayer-x86_64" -output "$APP_PATH/Contents/MacOS/notchplayer"
/usr/libexec/PlistBuddy -c 'Clear dict' "$APP_PATH/Contents/Info.plist"
/usr/libexec/PlistBuddy -c 'Add :CFBundleExecutable string notchplayer' -c 'Add :CFBundleIdentifier string local.nooklab.prototype' -c 'Add :CFBundleName string notchplayer' -c 'Add :CFBundleDisplayName string notchplayer' -c 'Add :CFBundlePackageType string APPL' -c 'Add :CFBundleShortVersionString string 0.2.63' -c 'Add :CFBundleVersion string 1' -c 'Add :NSAudioCaptureUsageDescription string 读取当前音乐播放器的音频以显示实时高低频波形；仅在内存分析，不保存或上传音频。' -c 'Add :LSMinimumSystemVersion string 14.0' -c 'Add :LSUIElement bool true' -c 'Add :NSHighResolutionCapable bool true' "$APP_PATH/Contents/Info.plist"
mkdir -p "$APP_PATH/Contents/Resources"
xcrun clang -dynamiclib -fobjc-arc -fvisibility=default -arch arm64 -arch x86_64 -mmacosx-version-min=14.0 -I Vendor/mediaremote-adapter/include -I Vendor/mediaremote-adapter/src Vendor/mediaremote-adapter/src/adapter/*.m Vendor/mediaremote-adapter/src/private/*.m Vendor/mediaremote-adapter/src/utility/*.m -framework Foundation -framework AppKit -framework UniformTypeIdentifiers -o MediaRemoteAdapter.framework/MediaRemoteAdapter
ditto --norsrc MediaRemoteAdapter.framework "$APP_PATH/Contents/Resources/MediaRemoteAdapter.framework"
cp Vendor/mediaremote-adapter/bin/mediaremote-adapter.pl "$APP_PATH/Contents/Resources/"
cp 使用说明.txt NOTICE.md "$APP_PATH/Contents/Resources/"
cp Vendor/mediaremote-adapter/LICENSE "$APP_PATH/Contents/Resources/MediaRemoteAdapter-LICENSE.txt"
xattr -dr com.apple.FinderInfo "$APP_PATH" 2>/dev/null || true
xattr -dr com.apple.ResourceFork "$APP_PATH" 2>/dev/null || true
codesign --force --deep --sign - "$APP_PATH"
print "Built: $APP_PATH"
