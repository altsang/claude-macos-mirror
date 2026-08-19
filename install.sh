#!/bin/bash
# install.sh — deploy the handoff tooling into the iCloud tree on this Mac.
#
# Idempotent. Touches ONLY tooling: never writes, moves or deletes project data.
#
#   ./install.sh                    deploy tool + skill bundles
#   ./install.sh --link <Project>   also symlink ~/Documents/Claude/Projects/<Project>
#   ./install.sh --check            report state, change nothing

set -uo pipefail
HERE="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
ROOT="$HOME/Library/Mobile Documents/com~apple~CloudDocs/Claude"
PROJECTS="$ROOT/Projects"
HANDOFF="$ROOT/_handoff"
ME="$(scutil --get ComputerName 2>/dev/null || hostname)"

die(){ echo "error: $*" >&2; exit 1; }
ok(){ echo "  ✓ $*"; }

check(){
  echo "machine: $ME"
  echo "iCloud account: $(defaults read MobileMeAccounts Accounts 2>/dev/null | awk -F'"' '/AccountID/{print $2; exit}')"
  [ -d "$ROOT" ] && ok "shared tree present: $ROOT" || echo "  ✗ shared tree missing (iCloud not synced yet?)"
  if [ -d "$HANDOFF/bin" ]; then
    # note: no `xargs basename` here — the path contains spaces and xargs splits on them
    newest="$(ls -1 "$HANDOFF"/bin/coworkctl-v*.sh 2>/dev/null | sort -V | tail -1)"
    [ -n "$newest" ] && ok "tool: $(basename "$newest")" || echo "  ✗ no coworkctl-v*.sh deployed"
  else
    echo "  ✗ tool not deployed"
  fi
  echo "  projects in shared tree:"
  for d in "$PROJECTS"/*/; do [ -d "$d" ] && echo "      $(basename "$d")"; done
  echo "  local symlinks:"
  for l in "$HOME/Documents/Claude/Projects"/*; do
    [ -L "$l" ] && echo "      $(basename "$l") -> $(readlink "$l")"
  done
}

link_project(){
  local name="$1"
  [ -d "$PROJECTS/$name" ] || die "'$name' is not in the shared tree ($PROJECTS)"
  local dest="$HOME/Documents/Claude/Projects/$name"
  mkdir -p "$HOME/Documents/Claude/Projects"
  if [ -L "$dest" ]; then
    ok "symlink already present: $dest"
  elif [ -e "$dest" ]; then
    # Never clobber real data. Make the human decide.
    die "$dest already exists and is NOT a symlink.
     Move it aside yourself first, e.g.:
       mv \"$dest\" \"$dest.pre-icloud-\$(date +%Y%m%d-%H%M%S)\"
     then re-run. Refusing to touch real project files."
  else
    ln -s "$PROJECTS/$name" "$dest"
    ok "symlinked $dest -> $PROJECTS/$name"
  fi
}

case "${1:-}" in
  --check) check; exit 0;;
esac

[ -d "$HOME/Library/Mobile Documents/com~apple~CloudDocs" ] \
  || die "iCloud Drive not available. Sign in to iCloud and enable Drive first."

mkdir -p "$PROJECTS" "$HANDOFF/bin"
ok "tree ready: $ROOT"

for f in "$HERE"/bin/coworkctl-v*.sh; do
  [ -f "$f" ] || continue
  cp "$f" "$HANDOFF/bin/$(basename "$f")"
  chmod +x "$HANDOFF/bin/$(basename "$f")"
  ok "deployed $(basename "$f")"
done
cp "$HERE/bin/VERSIONING.md" "$HANDOFF/bin/README.md" 2>/dev/null && ok "deployed bin/README.md"

# package skills as .skill bundles (a .skill is a zip of <name>/SKILL.md)
if command -v zip >/dev/null 2>&1; then
  tmp="$(mktemp -d)"
  for k in handoff pickup; do
    [ -f "$HERE/skills/$k/SKILL.md" ] || continue
    mkdir -p "$tmp/$k"; cp -R "$HERE/skills/$k/." "$tmp/$k/"
    (cd "$tmp" && rm -f "$HANDOFF/$k.skill" && zip -q -D -r "$HANDOFF/$k.skill" "$k" -x '.*')
    ok "packaged $k.skill"
  done
  rm -rf "$tmp"
else
  echo "  ! zip not found — skill bundles not packaged"
fi

if [ "${1:-}" = "--link" ]; then
  [ -n "${2:-}" ] || die "--link needs a project name"
  link_project "$2"
fi

echo
echo "Next, once per project, in the Claude desktop app:"
echo "  1. start a Cowork session on this Mac (a space from the other Mac will NOT appear here)"
echo "  2. grant it ~/Documents/Claude/Projects/<Name>"
echo "  3. import $HANDOFF/{handoff,pickup}.skill if they are not already in your skills list"
echo
echo "Then: bash \"\$(ls -1 '$HANDOFF'/bin/coworkctl-v*.sh | sort -V | tail -1)\" status"
