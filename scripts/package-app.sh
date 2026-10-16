#!/bin/bash
set -euo pipefail

ROOT="$(cd "$(dirname "$0")/.." && pwd)"
cd "$ROOT"

if pgrep -q SpotifyBar; then
  killall SpotifyBar 2>/dev/null || true
  sleep 0.4
fi

swift build -c release --product SpotifyBar
BIN="$(swift build -c release --show-bin-path)/SpotifyBar"

TMP="$(mktemp -d /tmp/SpotifyBar.XXXXXX)"
APP="$TMP/SpotifyBar.app"
mkdir -p "$APP/Contents/MacOS"
COPYFILE_DISABLE=1 cp "$BIN" "$APP/Contents/MacOS/SpotifyBar"
COPYFILE_DISABLE=1 cp "$ROOT/Info.plist" "$APP/Contents/Info.plist"
echo -n "APPL????" > "$APP/Contents/PkgInfo"
xattr -cr "$APP" 2>/dev/null || true
codesign --force --sign - "$APP/Contents/MacOS/SpotifyBar"
codesign --force --sign - "$APP"

DEST="$ROOT/dist/SpotifyBar.app"
rm -rf "$DEST"
mkdir -p "$ROOT/dist"
COPYFILE_DISABLE=1 cp -R "$APP" "$DEST"
xattr -cr "$DEST" 2>/dev/null || true

echo "Built $DEST"
echo "Open it with:  open \"$DEST\""
