#!/bin/sh
# Writes one version into every file a desktop app reads its own from, in the checkout a release builds, so a release
# made on a merge to main carries the version its tag names without a commit back to main.
# Perl, since it edits in place alike on macOS, Linux and the Git Bash of a Windows runner.
#   sh scripts/stamp-version.sh 0.1.7
set -e
VERSION="$1"
echo "$VERSION" | grep -Eq '^[0-9]+\.[0-9]+\.[0-9]+$' || { echo "usage: scripts/stamp-version.sh <major.minor.patch>" >&2; exit 1; }
cd "$(dirname "$0")/.."

for json in shared/tauri-core/package.json shared/tauri-core/src-tauri/tauri.conf.json; do
  perl -0pi -e 's/("version":\s*")[^"]*"/${1}'"$VERSION"'"/' "$json"
done
# The bundle version is one whole number made of the three, so it rises with every release and stays above the 6
# the Mac carried before versions were stamped: 0.1.7 is 1007, 1.2.3 is 1002003.
BUILD="$(echo "$VERSION" | awk -F. '{ print $1 * 1000000 + $2 * 1000 + $3 }')"
perl -0pi -e 's/(<key>CFBundleShortVersionString<\/key>\s*<string>)[^<]*/${1}'"$VERSION"'/; s/(<key>CFBundleVersion<\/key>\s*<string>)[^<]*/${1}'"$BUILD"'/' \
  macos/Support/Info.plist

grep -q "\"version\": \"$VERSION\"" shared/tauri-core/src-tauri/tauri.conf.json \
  && grep -q "<string>$VERSION</string>" macos/Support/Info.plist \
  && grep -q "<string>$BUILD</string>" macos/Support/Info.plist \
  || { echo "the version did not land in every file" >&2; exit 1; }
echo "stamped $VERSION"
