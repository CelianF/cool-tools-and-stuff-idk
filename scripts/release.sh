#!/bin/zsh
# Builds a signed "Cool Tools.app" (Apple Silicon), notarizes it and publishes a GitHub release.
#
#   scripts/release.sh 1.0.0          Developer ID signed + notarized (opens on any Mac)
#   scripts/release.sh 1.0.0 --dev    Apple Development signed, not notarized (others must allow it
#                                     in System Settings → Privacy & Security → Open Anyway)
#
# The default mode needs a Developer ID Application certificate and notarization credentials, either
#   - installed: the certificate in your keychain + `xcrun notarytool store-credentials cooltools-notary`, or
#   - as files (nothing is added to your keychain; a temporary one is used and deleted):
#       SIGNING_P12=…/developer_id.p12 SIGNING_P12_PASSWORD_FILE=…/p12_password.txt
#       NOTARY_KEY=…/AuthKey_XXXXXXXXXX.p8 [NOTARY_ISSUER=<issuer uuid, for team keys>]
set -euo pipefail
cd "${0:A:h}/.."

VERSION="${1:?usage: scripts/release.sh <version> [--dev]}"
MODE="${2:-}"
TAG="v$VERSION"
ZIP="build/Cool-Tools-$VERSION.zip"
NOTARY_PROFILE="${NOTARY_PROFILE:-cooltools-notary}"

KEYCHAIN=""
ORIGINAL_KEYCHAINS=(${(f)"$(security list-keychains -d user | tr -d '"' | sed 's/^ *//')"})
cleanup() {
  [[ -n "$KEYCHAIN" ]] || return 0
  security list-keychains -d user -s "${ORIGINAL_KEYCHAINS[@]}"
  security delete-keychain "$KEYCHAIN" 2>/dev/null || true
  rm -rf "${KEYCHAIN:h}"
}
trap cleanup EXIT

if [[ -n "${SIGNING_P12:-}" ]]; then
  # Throwaway keychain with a random password; codesign needs it in the search list for the chain.
  KEYCHAIN="$(mktemp -d)/signing.keychain-db"
  KC_PASS="$(uuidgen)"
  security create-keychain -p "$KC_PASS" "$KEYCHAIN"
  security set-keychain-settings -lut 3600 "$KEYCHAIN"
  security unlock-keychain -p "$KC_PASS" "$KEYCHAIN"
  security import "$SIGNING_P12" -k "$KEYCHAIN" -P "$(cat "$SIGNING_P12_PASSWORD_FILE")" -T /usr/bin/codesign >/dev/null
  security set-key-partition-list -S apple-tool:,apple:,codesign: -s -k "$KC_PASS" "$KEYCHAIN" >/dev/null
  security list-keychains -d user -s "$KEYCHAIN" "${ORIGINAL_KEYCHAINS[@]}"
fi

if [[ "$MODE" == "--dev" ]]; then
  IDENTITY="$(security find-identity -v -p codesigning | awk '/Apple Development/ {print $2; exit}')"
else
  # Use the SHA-1 fingerprint: names with accents don't always match codesign's lookup.
  IDENTITY="$(security find-identity -v -p codesigning ${KEYCHAIN:+"$KEYCHAIN"} | awk '/Developer ID Application/ {print $2; exit}')"
  [[ -n "$IDENTITY" ]] || { echo "No Developer ID Application certificate (see setup above), or pass --dev." >&2; exit 1; }
fi
[[ -n "${DRY_RUN:-}" || -z "$(git status --porcelain)" ]] || { echo "Commit your changes first." >&2; exit 1; }

VERSION="$VERSION" CODESIGN_IDENTITY="$IDENTITY" CODESIGN_KEYCHAIN="$KEYCHAIN" scripts/build.sh
APP="build/Cool Tools.app"
codesign --verify --deep --strict "$APP"

rm -f "$ZIP"
if [[ "$MODE" != "--dev" ]]; then
  ditto -c -k --keepParent "$APP" "$ZIP"
  if [[ -n "${NOTARY_KEY:-}" ]]; then
    KEY_ID="${${NOTARY_KEY:t:r}#AuthKey_}"
    xcrun notarytool submit "$ZIP" --key "$NOTARY_KEY" --key-id "$KEY_ID" ${NOTARY_ISSUER:+--issuer "$NOTARY_ISSUER"} --wait
  else
    xcrun notarytool submit "$ZIP" --keychain-profile "$NOTARY_PROFILE" --wait
  fi
  xcrun stapler staple "$APP"
  spctl --assess --type execute -vv "$APP"
  rm -f "$ZIP"
fi
ditto -c -k --keepParent "$APP" "$ZIP"

NOTES="Download **Cool-Tools-$VERSION.zip**, unzip, and move **Cool Tools.app** to Applications.
On first launch, allow it in System Settings → Privacy & Security → Accessibility."
[[ "$MODE" == "--dev" ]] && NOTES+="

This build isn't notarized: the first time, macOS will refuse to open it. Go to System Settings → Privacy & Security and click **Open Anyway**."

if [[ -n "${DRY_RUN:-}" ]]; then echo "Dry run: $ZIP is ready, nothing published."; exit 0; fi
git tag -a "$TAG" -m "Cool Tools $VERSION"
git push origin "$TAG"
gh release create "$TAG" "$ZIP" --title "Cool Tools $VERSION" --notes "$NOTES"
