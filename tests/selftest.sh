#!/usr/bin/env bash
# Installs the squad into a throwaway repo twice and fails unless the second run is a no-op.
set -euo pipefail
S="$(cd "$(dirname "$0")/.." && pwd)/setup-squad/scripts/setup_squad.py"
T="$(mktemp -d)"; trap 'rm -rf "$T"' EXIT
git -C "$T" init -q && git -C "$T" -c user.name=t -c user.email=t@t commit -q --allow-empty -m init

python3 "$S" --apply --repo "$T" >/dev/null
OUT="$(python3 "$S" --apply --repo "$T")"
CHANGED="$(sed -n '/== Structure ==/,/== Verify ==/p' <<<"$OUT" | grep '^\[' | grep -vE '\[ +(same|unchanged) +\]' || true)"
[ -z "$CHANGED" ] || { echo "FAIL: second apply changed files:"; echo "$CHANGED"; exit 1; }
tail -n 1 <<<"$OUT" | grep -qx ok || { echo "FAIL: verify"; echo "$OUT"; exit 1; }
echo "PASS"
