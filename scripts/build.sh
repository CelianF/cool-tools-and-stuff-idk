#!/bin/zsh
# Builds "Cool Tools.app" into build/. Pass --install to copy it to /Applications and (re)launch it.
set -euo pipefail
cd "${0:A:h}/.."

APP="build/Cool Tools.app"
swift build -c release --arch arm64
BIN="$(swift build -c release --arch arm64 --show-bin-path)/CoolTools"

rm -rf "$APP"
mkdir -p "$APP/Contents/MacOS" "$APP/Contents/Resources"
cp "$BIN" "$APP/Contents/MacOS/CoolTools"
cp Resources/Info.plist "$APP/Contents/Info.plist"
cp Resources/AppIcon.icns Resources/emoji.json "$APP/Contents/Resources/"
cp -R Resources/Shortcuts "$APP/Contents/Resources/Shortcuts"

# A stable signing identity keeps the Accessibility permission across rebuilds (ad-hoc signatures lose it).
IDENTITY="${CODESIGN_IDENTITY:-$(security find-identity -v -p codesigning | awk -F'"' '/Apple Development/ {print $2; exit}')}"
codesign --force --options runtime --sign "${IDENTITY:--}" "$APP"
echo "Built $APP (signed with ${IDENTITY:-ad-hoc})"

if [[ "${1:-}" == "--install" ]]; then
  pkill -x CoolTools || true
  rm -rf "/Applications/Cool Tools.app"
  cp -R "$APP" "/Applications/Cool Tools.app"
  open "/Applications/Cool Tools.app"
  echo "Installed to /Applications"
fi
