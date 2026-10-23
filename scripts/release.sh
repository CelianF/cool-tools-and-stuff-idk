#!/bin/zsh
# Builds a universal, signed "Cool Tools.app", notarizes it and publishes a GitHub release.
#
#   scripts/release.sh 1.0.0          Developer ID signed + notarized (opens on any Mac)
#   scripts/release.sh 1.0.0 --dev    Apple Development signed, not notarized (others must allow it
#                                     in System Settings → Privacy & Security → Open Anyway)
#
# One-time setup for the default mode:
#   1. Xcode → Settings → Accounts → Manage Certificates → + → Developer ID Application
#   2. xcrun notarytool store-credentials cooltools-notary --apple-id <you> --team-id <team>
set -euo pipefail
cd "${0:A:h}/.."

VERSION="${1:?usage: scripts/release.sh <version> [--dev]}"
MODE="${2:-}"
TAG="v$VERSION"
ZIP="build/Cool-Tools-$VERSION.zip"
NOTARY_PROFILE="${NOTARY_PROFILE:-cooltools-notary}"

if [[ "$MODE" == "--dev" ]]; then
  IDENTITY="$(security find-identity -v -p codesigning | awk -F'"' '/Apple Development/ {print $2; exit}')"
else
  IDENTITY="$(security find-identity -v -p codesigning | awk -F'"' '/Developer ID Application/ {print $2; exit}')"
  [[ -n "$IDENTITY" ]] || { echo "No Developer ID Application certificate (see setup above), or pass --dev." >&2; exit 1; }
fi
[[ -z "$(git status --porcelain)" ]] || { echo "Commit your changes first." >&2; exit 1; }

VERSION="$VERSION" UNIVERSAL=1 CODESIGN_IDENTITY="$IDENTITY" scripts/build.sh
APP="build/Cool Tools.app"
codesign --verify --deep --strict "$APP"

rm -f "$ZIP"
if [[ "$MODE" != "--dev" ]]; then
  ditto -c -k --keepParent "$APP" "$ZIP"
  xcrun notarytool submit "$ZIP" --keychain-profile "$NOTARY_PROFILE" --wait
  xcrun stapler staple "$APP"
  spctl --assess --type execute -vv "$APP"
  rm -f "$ZIP"
fi
ditto -c -k --keepParent "$APP" "$ZIP"

NOTES="Download **Cool-Tools-$VERSION.zip**, unzip, and move **Cool Tools.app** to Applications.
On first launch, allow it in System Settings → Privacy & Security → Accessibility."
[[ "$MODE" == "--dev" ]] && NOTES+="

This build isn't notarized: the first time, macOS will refuse to open it. Go to System Settings → Privacy & Security and click **Open Anyway**."

git tag -a "$TAG" -m "Cool Tools $VERSION"
git push origin "$TAG"
gh release create "$TAG" "$ZIP" --title "Cool Tools $VERSION" --notes "$NOTES"
