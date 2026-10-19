#!/bin/zsh
set -euo pipefail
cd "${0:A:h:h}"
zsh Tools/prepare-sparkle.sh
APP_PATH="$PWD/dist/notchplayer.app"
VERSION=$(/usr/libexec/PlistBuddy -c 'Print :CFBundleShortVersionString' "$APP_PATH/Contents/Info.plist")
PACKAGE="notchplayer-$VERSION-macOS-universal"
RELEASE_STAGE=$(mktemp -d "${TMPDIR:-/tmp/}notchplayer-release.XXXXXX")
mkdir -p "$RELEASE_STAGE/dmg" "$RELEASE_STAGE/feed"
# A clean staging folder prevents Desktop sync metadata from invalidating the signature.
ditto --norsrc "$APP_PATH" "$RELEASE_STAGE/dmg/notchplayer.app"
xattr -cr "$RELEASE_STAGE/dmg/notchplayer.app"
codesign --force --deep --sign - "$RELEASE_STAGE/dmg/notchplayer.app"
codesign --verify --deep --strict "$RELEASE_STAGE/dmg/notchplayer.app"
ditto -c -k --sequesterRsrc --keepParent "$RELEASE_STAGE/dmg/notchplayer.app" "$RELEASE_STAGE/feed/$PACKAGE.zip"
ln -s /Applications "$RELEASE_STAGE/dmg/Applications"
cp 使用说明.txt "$RELEASE_STAGE/dmg/"
hdiutil create -quiet -volname "notchplayer $VERSION" -srcfolder "$RELEASE_STAGE/dmg" -ov -format UDZO "$RELEASE_STAGE/$PACKAGE.dmg"
hdiutil verify -quiet "$RELEASE_STAGE/$PACKAGE.dmg"
if git ls-files --error-unmatch Releases/appcast.xml >/dev/null 2>&1; then cp Releases/appcast.xml "$RELEASE_STAGE/feed/appcast.xml"; fi
if [[ -f "Releases/v$VERSION.md" ]]; then cp "Releases/v$VERSION.md" "$RELEASE_STAGE/feed/$PACKAGE.md"; fi
.build/Sparkle/bin/generate_appcast --account thorpjia-cloud.notchplayer --maximum-deltas 0 --maximum-versions 0 --embed-release-notes --download-url-prefix "https://github.com/thorpjia-cloud/notchplayer/releases/download/v$VERSION/" "$RELEASE_STAGE/feed"
# Published packages and tags are immutable; a new build must use a new version.
for EXT in zip dmg; do
  DEST="Releases/$PACKAGE.$EXT"
  SOURCE="$RELEASE_STAGE/$PACKAGE.$EXT"
  [[ "$EXT" == zip ]] && SOURCE="$RELEASE_STAGE/feed/$PACKAGE.zip"
  if git ls-files --error-unmatch "$DEST" >/dev/null 2>&1; then
    print -u2 "Already tracked: $DEST. Increase the app version before packaging."
    exit 1
  fi
  cp "$SOURCE" "$DEST"
done
cp "$RELEASE_STAGE/feed/appcast.xml" Releases/appcast.xml
# Replace only uncommitted checksums from repeated validation of this version.
python3 - "$PACKAGE" <<'PY'
from pathlib import Path
import sys
path = Path('Releases/SHA256SUMS')
path.write_text(''.join(line for line in path.read_text().splitlines(keepends=True) if sys.argv[1] + '.' not in line))
PY
shasum -a 256 "Releases/$PACKAGE.dmg" "Releases/$PACKAGE.zip" >> Releases/SHA256SUMS
print -r -- "$RELEASE_STAGE" > .build/latest-release-stage.txt
print "Prepared $VERSION: $RELEASE_STAGE"
