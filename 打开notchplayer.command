#!/bin/zsh
set -euo pipefail
if [[ -d /Applications/notchplayer.app ]]; then
  open /Applications/notchplayer.app
else
  # Keep the previous per-user installation usable after updating the source.
  open "$HOME/Applications/notchplayer.app"
fi
