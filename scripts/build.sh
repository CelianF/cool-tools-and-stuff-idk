#!/bin/zsh
# Builds "Cool Tools.app" into build/. Pass --install to copy it to /Applications and (re)launch it.
# Env: VERSION=1.2.0 sets the bundle version, UNIVERSAL=1 builds arm64 + x86_64,
#      CODESIGN_IDENTITY picks the signing certificate (default: Apple Development).
set -euo pipefail
cd "${0:A:h}/.."

APP="build/Cool Tools.app"
ARCHS=(--arch arm64)
[[ "${UNIVERSAL:-}" == 1 ]] && ARCHS+=(--arch x86_64)
swift build -c release "${ARCHS[@]}"
BIN="$(swift build -c release "${ARCHS[@]}" --show-bin-path)/CoolTools"

rm -rf "$APP"
mkdir -p "$APP/Contents/MacOS" "$APP/Contents/Resources"
cp "$BIN" "$APP/Contents/MacOS/CoolTools"
cp Resources/Info.plist "$APP/Contents/Info.plist"
cp Resources/AppIcon.icns Resources/emoji.json "$APP/Contents/Resources/"
if [[ -n "${VERSION:-}" ]]; then
  /usr/libexec/PlistBuddy -c "Set :CFBundleShortVersionString $VERSION" -c "Set :CFBundleVersion $VERSION" "$APP/Contents/Info.plist"
fi

# A stable signing identity keeps the Accessibility permission across rebuilds (ad-hoc signatures lose it).
IDENTITY="${CODESIGN_IDENTITY:-$(security find-identity -v -p codesigning | awk -F'"' '/Apple Development/ {print $2; exit}')}"
codesign --force --options runtime --timestamp --entitlements Resources/CoolTools.entitlements --sign "${IDENTITY:--}" "$APP"
echo "Built $APP (signed with ${IDENTITY:-ad-hoc})"

if [[ "${1:-}" == "--install" ]]; then
  pkill -x CoolTools || true
  rm -rf "/Applications/Cool Tools.app"
  cp -R "$APP" "/Applications/Cool Tools.app"
  open "/Applications/Cool Tools.app"
  echo "Installed to /Applications"
fi
