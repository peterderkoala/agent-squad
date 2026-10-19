#!/usr/bin/env bash
# Installer: second apply is a no-op, upgrade restores owned files and keeps state.
# ralph.sh: stop file and failure cap, with a fake claude.
set -euo pipefail
S="$(cd "$(dirname "$0")/.." && pwd)/setup-squad/scripts/setup_squad.py"
T="$(mktemp -d)"; trap 'rm -rf "$T"' EXIT
fail() { echo "FAIL: $*"; exit 1; }
git -C "$T" init -q && git -C "$T" -c user.name=t -c user.email=t@t commit -q --allow-empty -m init

python3 "$S" --apply --repo "$T" >/dev/null
OUT="$(python3 "$S" --apply --repo "$T")"
CHANGED="$(sed -n '/== Structure ==/,/== Verify ==/p' <<<"$OUT" | grep '^\[' | grep -vE '\[ +(same|unchanged) +\]' || true)"
[ -z "$CHANGED" ] || fail "second apply changed files: $CHANGED"
tail -n 1 <<<"$OUT" | grep -qx ok || fail "verify: $OUT"

echo local >> "$T/.claude/agents/developer.md"
echo local >> "$T/.mysquad/PLAN.md"
python3 "$S" --apply --repo "$T" | grep -q 'kept (differs).*developer.md' || fail "apply overwrote an owned file"
python3 "$S" --upgrade --repo "$T" | grep -q 'upgraded.*developer.md' || fail "upgrade did not restore developer.md"
grep -q local "$T/.claude/agents/developer.md" && fail "developer.md still has local edit"
grep -q local "$T/.mysquad/PLAN.md" || fail "upgrade touched state file PLAN.md"

# ralph.sh with fake claude (always fails) and fake code-review-graph
mkdir -p "$T/bin" "$T/.claude/skills/review-changes" "$T/.code-review-graph"
printf '#!/bin/sh\nexit 1\n' > "$T/bin/claude"; printf '#!/bin/sh\nexit 0\n' > "$T/bin/code-review-graph"
chmod +x "$T/bin/"*
sed -i 's/<describe[^>]*>/test goal/' "$T/.mysquad/PLAN.md"
ralph() { (cd "$T" && PATH="$T/bin:$PATH" SQUAD_MAX_FAILS=1 .mysquad/ralph.sh 3 >/dev/null 2>&1); }
touch "$T/.mysquad/stop"
set +e; ralph; RC=$?; set -e
[ "$RC" = 3 ] || fail "stop file: exit $RC, want 3"
[ -e "$T/.mysquad/stop" ] && fail "stop file not removed"
set +e; ralph; RC=$?; set -e
[ "$RC" = 4 ] || fail "failure cap: exit $RC, want 4"
echo "PASS"
