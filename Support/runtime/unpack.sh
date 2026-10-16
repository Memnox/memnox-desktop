#!/bin/sh
# Puts the runtime this app carries, memnox with its own Node, into ~/.memnox/node, so a Mac with no Node and no
# connection still gets memnox on first launch. Rides inside the app beside the archive and its version, and the app
# runs it at every launch: a runtime already there that is as new is left alone at once, so only an older one or
# none at all is ever unpacked, and an update memnox update already took is never rolled back.
set -e
HERE="$(cd "$(dirname "$0")" && pwd)"
NODE="${MEMNOX_NODE_DIR:-$HOME/.memnox/node}"
ARCHIVE="$HERE/memnox-runtime.tar.xz"
NEW="$(cat "$HERE/memnox-runtime.version")"
# Beside the real folder, so a half unpacked runtime never takes its place.
STAGING="$NODE-unpacking"

version() { "$1/bin/node" -p "JSON.parse(require('fs').readFileSync(process.argv[1])).version" "$2/lib/node_modules/memnox/package.json" 2>/dev/null; }
# Exits 0 when the first version is newer than the second.
NEWER="const [a, b] = process.argv.slice(1).map((v) => v.split('-')[0].split('.').map(Number));
for (let i = 0; i < 3; i++) if ((a[i] || 0) !== (b[i] || 0)) process.exit((a[i] || 0) > (b[i] || 0) ? 0 : 1);
process.exit(1);"

# The terminal Memnox opens to start a session types memnox by name, as the person does in their own, and neither
# finds it until this folder is on the PATH. So the profile their shell reads gets one fenced line, once, with its
# own markers, apart from the block memnox protect --path writes. MEMNOX_PROFILE names another file, for a test.
onPath() {
  BEGIN="# >>> memnox app >>>"
  END="# <<< memnox app <<<"
  case "$(basename "${SHELL:-zsh}")" in
    fish) PROFILE="$HOME/.config/fish/config.fish"; LINE="fish_add_path --prepend $NODE/bin" ;;
    bash) PROFILE="$HOME/.bash_profile"; LINE="export PATH=\"$NODE/bin:\$PATH\"" ;;
    *) PROFILE="$HOME/.zshrc"; LINE="export PATH=\"$NODE/bin:\$PATH\"" ;;
  esac
  PROFILE="${MEMNOX_PROFILE:-$PROFILE}"
  grep -qF "$BEGIN" "$PROFILE" 2>/dev/null && return 0
  mkdir -p "$(dirname "$PROFILE")"
  printf '\n%s\n%s\n%s\n%s\n' "$BEGIN" "# Added by Memnox.app so a terminal finds memnox. Delete these lines to undo." "$LINE" "$END" >> "$PROFILE"
  echo "put $NODE/bin on the PATH in $PROFILE"
}

if [ -x "$NODE/bin/node" ]; then
  OLD="$(version "$NODE" "$NODE" || true)"
  if [ -n "$OLD" ] && ! "$NODE/bin/node" -e "$NEWER" "$NEW" "$OLD"; then
    echo "memnox $OLD in $NODE is at least as new as $NEW, so it stays"
    onPath
    exit 0
  fi
fi

echo "STEP Putting Memnox on this Mac"
rm -rf "$STAGING"
mkdir -p "$STAGING"
trap 'rm -rf "$STAGING"' EXIT
tar -xJf "$ARCHIVE" -C "$STAGING"
# Proved before it replaces anything: the CLI answers under the Node it rides with.
"$STAGING/bin/node" "$STAGING/lib/node_modules/memnox/dist/index.js" --version >/dev/null
rm -rf "$NODE"
mv "$STAGING" "$NODE"
echo "memnox $NEW is in $NODE"
onPath
