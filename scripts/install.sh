#!/bin/bash
# Installs the latest Sotto release into /Applications:
#   curl -fsSL https://raw.githubusercontent.com/FurkanCodes/Sotto/main/scripts/install.sh | bash
# Downloads the zip, checks its SHA-256, and asks whether macOS should check
# the app before its first launch. Read it before running it.
set -euo pipefail

REPO="FurkanCodes/Sotto"
DEST="${SOTTO_INSTALL_DIR:-/Applications}"

say() { printf '%s\n' "$*"; }
fail() { printf 'error: %s\n' "$*" >&2; exit 1; }

[ "$(uname -s)" = Darwin ] || fail "Sotto runs only on macOS."
[ "$(uname -m)" = arm64 ] || fail "Sotto needs a Mac with Apple silicon (M1 or later)."
major="$(sw_vers -productVersion | cut -d. -f1)"
[ "$major" -ge 26 ] || fail "Sotto needs macOS 26 or later; this Mac has $(sw_vers -productVersion)."

say "Finding the latest Sotto release..."
version="${SOTTO_VERSION:-$(curl -fsSL "https://api.github.com/repos/$REPO/releases/latest" \
  | sed -n 's/.*"tag_name": *"v\([^"]*\)".*/\1/p' | head -n 1)}"
[ -n "$version" ] || fail "couldn't find the latest release on GitHub."
name="Sotto-$version.zip"
url="https://github.com/$REPO/releases/download/v$version"

work="$(mktemp -d)"
trap 'rm -rf "$work"' EXIT

say "Downloading Sotto $version..."
curl -fL --progress-bar -o "$work/$name" "$url/$name"
curl -fsSL -o "$work/$name.sha256" "$url/$name.sha256"

say "Checking the download..."
(cd "$work" && shasum -a 256 -c "$name.sha256" >/dev/null) \
  || fail "the download doesn't match its checksum; nothing was installed."

ditto -x -k "$work/$name" "$work/unpacked"
[ -d "$work/unpacked/Sotto.app" ] || fail "the zip doesn't contain Sotto.app."

cat <<'EOF'

A quick heads-up before installing
----------------------------------
Hi! Sotto is a one-person project, and I don't have a paid Apple Developer
account yet. That means Apple hasn't "notarized" Sotto, their stamp that
says an app was checked. Once I get the account, I'll notarize Sotto and
this question goes away.

Until then, macOS blocks apps without that stamp the first time they open.
The app itself is fine: it's signed, it's open source, and the download was
just checked against the release's checksum. But it's your Mac, so you
decide how to open it:

  YES: skip Apple's check, and Sotto opens right away.
  NO:  keep Apple's check. macOS blocks Sotto the first time, and you allow
       it once in System Settings -> Privacy & Security -> Open Anyway.

Either way you get the same app. Pick NO if you'd rather let macOS check it.
EOF

answer=""
if [ -r /dev/tty ] && { exec 3</dev/tty; } 2>/dev/null; then
  while :; do
    printf '\nOK to open Sotto without Apple'"'"'s check? [yes/no]: ' >/dev/tty
    read -r answer <&3 || answer=""
    case "$(printf '%s' "$answer" | tr '[:upper:]' '[:lower:]')" in
      y|yes) answer=yes; break ;;
      n|no)  answer=no;  break ;;
      "") ;;  # Enter alone, or a key pressed during the download: ask again
      *) say "Please type yes or no." ;;
    esac
  done
  exec 3<&-
else
  say "No terminal to ask in, so keeping the mark (NO)."
  answer=no
fi

app="$DEST/Sotto.app"
if [ -e "$app" ]; then
  if pgrep -xq Sotto; then
    say "Quitting the running Sotto..."
    osascript -e 'quit app "Sotto"' >/dev/null 2>&1 || true
    sleep 2
  fi
  say "Replacing $app..."
  rm -rf "$app" 2>/dev/null || sudo rm -rf "$app"
fi
mkdir -p "$DEST"
ditto "$work/unpacked/Sotto.app" "$app" 2>/dev/null || sudo ditto "$work/unpacked/Sotto.app" "$app"

if [ "$answer" = yes ]; then
  xattr -dr com.apple.quarantine "$app" 2>/dev/null || sudo xattr -dr com.apple.quarantine "$app"
  say ""
  say "Sotto $version is installed in $DEST. Opening it..."
  [ -n "${SOTTO_NO_OPEN:-}" ] || open "$app"
else
  mark="0081;$(printf '%x' "$(date +%s)");Sotto installer;"
  xattr -w com.apple.quarantine "$mark" "$app" 2>/dev/null \
    || sudo xattr -w com.apple.quarantine "$mark" "$app"
  say ""
  say "Sotto $version is installed in $DEST, with the mark."
  say "Open it from Applications. When macOS blocks it, click Done, then go to"
  say "System Settings -> Privacy & Security and click Open Anyway."
fi
