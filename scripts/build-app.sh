#!/usr/bin/env bash
# Builds build/Sotto.app (Apple Silicon) and signs it.
#
# Signing identity: $SOTTO_SIGN_IDENTITY, else the first "Apple Development"
# certificate, else the local self-signed "Sotto Local Signing" certificate,
# else ad-hoc. Any real certificate keeps the app's identity stable, so macOS
# keeps the Accessibility and Input Monitoring grants across rebuilds; ad-hoc
# builds lose them every time.
#
# Usage: scripts/build-app.sh [release|debug]
set -euo pipefail
cd "$(dirname "$0")/.."

config="${1:-release}"
scripts/build-transcribe.sh
swift build -c "$config" --arch arm64
bin_dir="$(swift build -c "$config" --arch arm64 --show-bin-path)"

app="build/Sotto.app"
rm -rf "$app"
mkdir -p "$app/Contents/MacOS" "$app/Contents/Resources"
cp "$bin_dir/Sotto" "$app/Contents/MacOS/Sotto"
cp Resources/Info.plist "$app/Contents/Info.plist"
cp THIRD_PARTY_NOTICES.md "$app/Contents/Resources/"
cp Resources/model-catalog.json "$app/Contents/Resources/"
# The app icon, from Icon Composer's format: macOS 26 draws it with Liquid
# Glass, and older-style icons get boxed in a gray frame. actool also writes
# AppIcon.icns for older places that read it.
xcrun actool Resources/AppIcon.icon --compile "$app/Contents/Resources" --platform macosx \
  --minimum-deployment-target 26.0 --app-icon AppIcon \
  --output-partial-info-plist "$(mktemp)" --errors --warnings --output-format human-readable-text >/dev/null

# The XPC helper that runs transcribe.cpp models in their own process.
helper="$app/Contents/XPCServices/SottoEngine.xpc"
mkdir -p "$helper/Contents/MacOS"
cp "$bin_dir/SottoEngine" "$helper/Contents/MacOS/SottoEngine"
cp Resources/SottoEngine-Info.plist "$helper/Contents/Info.plist"

# Local symbols are about 40% of the app; the unstripped binaries stay in .build.
if [[ "$config" == release ]]; then
  strip -x "$app/Contents/MacOS/Sotto" "$helper/Contents/MacOS/SottoEngine"
fi

identity="${SOTTO_SIGN_IDENTITY:-}"
if [[ -z "$identity" ]]; then
    identity="$(security find-identity -v -p codesigning | awk -F'"' '/Apple Development/ { print $2; exit }')"
fi
if [[ -z "$identity" ]] && security find-identity -p codesigning | grep -q '"Sotto Local Signing"'; then
    # Self-signed, so macOS lists it as not trusted; codesign still signs with it.
    identity="Sotto Local Signing"
fi
if [[ -z "$identity" ]]; then
    echo "warning: no signing certificate found, signing ad-hoc." >&2
    echo "         macOS will ask for Accessibility and Input Monitoring again after every build." >&2
    identity="-"
fi

codesign --force --options runtime --sign "$identity" "$helper"
codesign --force --options runtime --entitlements Resources/Sotto.entitlements --sign "$identity" "$app"
echo "$app"
