#!/bin/bash
# Builds Sotto.app and packs it for download: build/release/Sotto-<version>.zip
# and Sotto-<version>.zip.sha256. The app is signed but not notarized, so
# users open it once by hand (docs/INSTALL.md).
set -euo pipefail
cd "$(dirname "$0")/.."

scripts/build-app.sh release
app="build/Sotto.app"

# macOS keeps permissions per signing certificate. An ad-hoc build would make
# every user grant Accessibility, Input Monitoring and the mic again.
details="$(codesign -dvv "$app" 2>&1)"
if grep -q "Signature=adhoc" <<<"$details"; then
  echo "error: $app is ad-hoc signed; releases must use the same certificate every time" >&2
  exit 1
fi
codesign --verify --deep --strict "$app"
signer="$(awk -F= '/^Authority=/ {print $2; exit}' <<<"$details")"

version="$(/usr/libexec/PlistBuddy -c 'Print :CFBundleShortVersionString' "$app/Contents/Info.plist")"
mkdir -p build/release
name="Sotto-$version.zip"
zip="build/release/$name"
rm -f "$zip" "$zip.sha256"
# ditto keeps the code signature intact; a plain zip can break it.
ditto -c -k --sequesterRsrc --keepParent "$app" "$zip"
# Just the file name, so `shasum -c` works from the user's Downloads folder.
(cd build/release && shasum -a 256 "$name" > "$name.sha256")

echo "Signed by: $signer"
echo "$(du -h "$zip" | cut -f1)  $zip"
cat "$zip.sha256"
