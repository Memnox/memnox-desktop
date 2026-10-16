#!/bin/sh
# Builds the runtime pack: Node's own release for Apple silicon with the newest memnox published to npm installed into
# it by its own npm, in one archive, so the installer package puts memnox on a Mac that has no Node and no connection.
# Installed globally into that Node, so the layout is the one memnox update recognizes and updates in place.
# Leaves memnox-runtime.tar.xz and memnox-runtime.version in build/runtime. MEMNOX_RUNTIME_VERSION pins one release.
set -e
HERE="$(cd "$(dirname "$0")" && pwd)"
OUT="${1:-$HERE/../build/runtime}"
# The newest of the Node line the runtime's engines field asks for, checked against the checksums Node publishes.
NODE_LINE="latest-v22.x"
NODE_DIST="https://nodejs.org/dist/$NODE_LINE"
NODE="$OUT/node"
rm -rf "$OUT"
mkdir -p "$NODE"
OUT="$(cd "$OUT" && pwd)"
NODE="$OUT/node"

SUMS="$(curl -fsSL --retry 3 "$NODE_DIST/SHASUMS256.txt")"
TARBALL="$(echo "$SUMS" | awk '/darwin-arm64\.tar\.xz$/ { print $2 }')"
[ -n "$TARBALL" ] || { echo "Node's $NODE_LINE has no build for darwin-arm64"; exit 1; }
echo "Node $TARBALL"
curl -fL --retry 5 --retry-all-errors --retry-delay 2 "$NODE_DIST/$TARBALL" -o "$OUT/$TARBALL"
WANT="$(echo "$SUMS" | awk -v f="$TARBALL" '$2 == f { print $1 }')"
[ "$(shasum -a 256 "$OUT/$TARBALL" | cut -d' ' -f1)" = "$WANT" ] || { echo "$TARBALL did not match its checksum"; exit 1; }
tar -C "$NODE" --strip-components 1 -xJf "$OUT/$TARBALL"
rm "$OUT/$TARBALL"
# Headers and docs only matter to building native modules, which the runtime takes prebuilt.
rm -rf "$NODE/include" "$NODE/share" "$NODE/CHANGELOG.md" "$NODE/README.md"

SPEC="memnox@${MEMNOX_RUNTIME_VERSION:-latest}"
echo "Runtime $SPEC"
PATH="$NODE/bin:$PATH" NPM_CONFIG_PREFIX="$NODE" "$NODE/bin/npm" install -g --no-audit --no-fund "$SPEC"
PACKAGE="$NODE/lib/node_modules/memnox/package.json"
VERSION="$("$NODE/bin/node" -p "JSON.parse(require('fs').readFileSync(process.argv[1])).version" "$PACKAGE")"
# Proved before it ships: the CLI answers under the Node it rides with.
"$NODE/bin/node" "$NODE/lib/node_modules/memnox/dist/index.js" --version >/dev/null

XZ_OPT="-T0 -6" tar -C "$NODE" -cJf "$OUT/memnox-runtime.tar.xz" .
echo "$VERSION" > "$OUT/memnox-runtime.version"
rm -rf "$NODE"
du -h "$OUT/memnox-runtime.tar.xz" | cut -f1 | sed "s|^|memnox $VERSION with Node is |"
