#!/bin/zsh
set -euo pipefail
cd "${0:A:h:h}"
ARCHIVE=Vendor/Sparkle/Sparkle-2.10.0.tar.xz
EXPECTED=c2bf58aa8387266ac179357b1415d6f2635f044da8be41042af32425dae6da0c
ACTUAL=$(shasum -a 256 "$ARCHIVE" | cut -d ' ' -f 1)
[[ "$ACTUAL" == "$EXPECTED" ]] || { print -u2 'Sparkle archive checksum mismatch'; exit 1; }
if [[ ! -f .build/Sparkle/Sparkle.framework/Versions/B/Sparkle ]]; then
  mkdir -p .build/Sparkle
  tar -xf "$ARCHIVE" -C .build/Sparkle
fi
