#!/bin/zsh
set -euo pipefail
cd "${0:A:h}"
APP_PATH="$PWD/dist/notchplayer.app"
mkdir -p "$APP_PATH/Contents/MacOS"
xcrun swiftc -swift-version 5 -O -parse-as-library Sources/NotchPlayer.swift Sources/MediaService.swift Sources/AudioSpectrum.swift Sources/ArtworkPalette.swift Sources/MarqueeTitle.swift Sources/OutputVolume.swift Sources/GlassMotion.swift -o "$APP_PATH/Contents/MacOS/notchplayer" -framework AppKit -framework Accelerate -framework CoreAudio -framework AudioToolbox -framework SwiftUI -framework UniformTypeIdentifiers -target arm64-apple-macosx14.0
/usr/libexec/PlistBuddy -c 'Clear dict' "$APP_PATH/Contents/Info.plist"
/usr/libexec/PlistBuddy -c 'Add :CFBundleExecutable string notchplayer' -c 'Add :CFBundleIdentifier string local.nooklab.prototype' -c 'Add :CFBundleName string notchplayer' -c 'Add :CFBundleDisplayName string notchplayer' -c 'Add :CFBundlePackageType string APPL' -c 'Add :CFBundleShortVersionString string 0.2.61' -c 'Add :CFBundleVersion string 1' -c 'Add :NSAudioCaptureUsageDescription string 读取当前音乐播放器的音频以显示实时高低频波形；仅在内存分析，不保存或上传音频。' -c 'Add :LSMinimumSystemVersion string 14.0' -c 'Add :LSUIElement bool true' -c 'Add :NSHighResolutionCapable bool true' "$APP_PATH/Contents/Info.plist"
mkdir -p "$APP_PATH/Contents/Resources"
xcrun clang -dynamiclib -fobjc-arc -fvisibility=default -arch arm64 -mmacosx-version-min=14.0 -I Vendor/mediaremote-adapter/include -I Vendor/mediaremote-adapter/src Vendor/mediaremote-adapter/src/adapter/*.m Vendor/mediaremote-adapter/src/private/*.m Vendor/mediaremote-adapter/src/utility/*.m -framework Foundation -framework AppKit -framework UniformTypeIdentifiers -o MediaRemoteAdapter.framework/MediaRemoteAdapter
ditto --norsrc MediaRemoteAdapter.framework "$APP_PATH/Contents/Resources/MediaRemoteAdapter.framework"
cp Vendor/mediaremote-adapter/bin/mediaremote-adapter.pl "$APP_PATH/Contents/Resources/"
cp Vendor/mediaremote-adapter/LICENSE "$APP_PATH/Contents/Resources/MediaRemoteAdapter-LICENSE.txt"
xattr -dr com.apple.FinderInfo "$APP_PATH" 2>/dev/null || true
xattr -dr com.apple.ResourceFork "$APP_PATH" 2>/dev/null || true
codesign --force --deep --sign - "$APP_PATH"
print "Built: $APP_PATH"
