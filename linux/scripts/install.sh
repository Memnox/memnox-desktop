#!/bin/sh
# Installs Memnox for Linux from the newest release of memnox-desktop, checked against its SHA256SUMS:
#   curl -fsSL https://raw.githubusercontent.com/Memnox/memnox-desktop/main/linux/scripts/install.sh | sh
# The deb where apt is, the rpm where dnf or zypper is, and the AppImage in ~/.local/bin anywhere else.
set -eu

REPO="Memnox/memnox-desktop"
fail() { printf 'memnox install: %s\n' "$1" >&2; exit 1; }

[ "$(uname -s)" = Linux ] || fail "Memnox for Linux runs on Linux."
[ "$(uname -m)" = x86_64 ] || fail "this preview runs on x86_64 only."

# The newest release of the Windows and Linux app, a preview included, since the Mac app is released here too.
release=$(curl -fsSL "https://api.github.com/repos/$REPO/releases?per_page=30" \
  | grep -o '"browser_download_url": *"[^"]*/app-v[^"]*/SHA256SUMS"' | head -1 | sed 's/.*"\(https[^"]*\)\/SHA256SUMS"$/\1/')
[ -n "$release" ] || fail "could not find a release of Memnox for Linux."

if command -v apt-get >/dev/null 2>&1; then kind=deb
elif command -v dnf >/dev/null 2>&1 || command -v zypper >/dev/null 2>&1; then kind=rpm
else kind=AppImage
fi

work=$(mktemp -d)
trap 'rm -rf "$work"' EXIT
curl -fsSL --retry 3 "$release/SHA256SUMS" -o "$work/SHA256SUMS" || fail "could not download the checksums"
file=$(grep -o "[^ ]*\.$kind\$" "$work/SHA256SUMS" | head -1)
[ -n "$file" ] || fail "the release has no .$kind"

echo "Downloading $file"
curl -fL --progress-bar --retry 3 "$release/$file" -o "$work/$file" || fail "could not download $file"
# The download must match the checksum published with it, or nothing is installed.
(cd "$work" && grep " $file\$" SHA256SUMS | sha256sum -c --quiet -) || fail "$file does not match its published checksum, so it was not installed."

case $kind in
  deb) sudo apt-get install -y "$work/$file" ;;
  rpm) if command -v dnf >/dev/null 2>&1; then sudo dnf install -y "$work/$file"; else sudo zypper --non-interactive install "$work/$file"; fi ;;
  AppImage)
    mkdir -p "$HOME/.local/bin"
    install -m 755 "$work/$file" "$HOME/.local/bin/memnox-desktop.AppImage"
    # Without its polkit action nothing can be allowed from this computer, so the policy is put in place, checked first.
    policy=org.memnox.desktop.policy
    curl -fsSL --retry 3 "$release/$policy" -o "$work/$policy" || fail "could not download the polkit policy"
    (cd "$work" && grep " $policy\$" SHA256SUMS | sha256sum -c --quiet -) || fail "the polkit policy does not match its checksum"
    sudo install -m 644 "$work/$policy" /usr/share/polkit-1/actions/$policy
    echo "Memnox is in ~/.local/bin/memnox-desktop.AppImage."
    ;;
esac
echo "Memnox is installed. Open it from your applications; the first run asks to install its voice."
