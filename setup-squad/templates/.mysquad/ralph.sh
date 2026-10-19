#!/usr/bin/env bash
# Autonomous outer loop. Fresh context each round, state lives in files.
# Usage: .mysquad/ralph.sh [max_rounds]   (default 10)
set -uo pipefail

cd "$(git rev-parse --show-toplevel 2>/dev/null)" || { echo "Not a git repo."; exit 1; }
mkdir -p .mysquad/log

MAX="${1:-10}"
export PONYTAIL_DEFAULT_MODE=full
LEAD_MODEL="claude-opus-5-5"
STALE=0

# Human-in-the-loop: notify when the squad needs you.
# Set SQUAD_NOTIFY_CMD to a command that uses "$1" as the message, for example:
#   export SQUAD_NOTIFY_CMD='curl -s -H "Title: Squad" -d "$1" https://ntfy.sh/your-private-topic'
notify() {
  echo "[notify $(date +%H:%M)] $1" | tee -a .mysquad/log/notify.log
  if [ -n "${SQUAD_NOTIFY_CMD:-}" ]; then bash -c "$SQUAD_NOTIFY_CMD" _ "$1" >/dev/null 2>&1 || true; fi
}
open_questions() {
  awk '/^## Open questions/{f=1;next} /^## /{f=0} f && /Q-[0-9]+/ && !/ANSWER:/' .mysquad/STATUS.md
}
count_lines() { printf '%s' "$1" | grep -c . || true; }
finish() { notify "$1"; exit "$2"; }
N_OLD="$(count_lines "$(open_questions)")"

# .mysquad/SPEC.md is optional. Without it the goal in .mysquad/PLAN.md is the only input.
if [ -s .mysquad/SPEC.md ]; then
  SPEC_NOTE="Read .mysquad/SPEC.md first (source of truth)."
else
  SPEC_NOTE="There is no .mysquad/SPEC.md. Use the Goal in .mysquad/PLAN.md as input, work autonomously, record every assumption as an OPEN QUESTION in .mysquad/STATUS.md."
  grep -q '<describe' .mysquad/PLAN.md && { echo "No .mysquad/SPEC.md and .mysquad/PLAN.md has no goal. Run /grill-squad or fill the Goal."; exit 1; }
fi

# Code graph is required: one truth about the codebase
command -v code-review-graph >/dev/null || { echo "Install: pip install code-review-graph"; exit 1; }
[ -d .claude/skills/review-changes ] || { echo "Graph skills missing. Run once: code-review-graph install --platform claude-code"; exit 1; }
[ -d .code-review-graph ] || code-review-graph build

# Never work on main
git rev-parse --git-dir >/dev/null 2>&1 || { echo "Not a git repo."; exit 1; }
BRANCH="$(git rev-parse --abbrev-ref HEAD)"
if [ "$BRANCH" = "main" ] || [ "$BRANCH" = "master" ]; then
  git checkout -b squad/work
fi

for i in $(seq 1 "$MAX"); do
  if tail -n 1 .mysquad/STATUS.md | grep -q "ALL DONE"; then
    finish "Squad done after $((i-1)) rounds. Open questions: $N_OLD." 0
  fi

  code-review-graph update --brief || true
  BEFORE="$(git rev-parse HEAD)$(md5sum .mysquad/STATUS.md .mysquad/PLAN.md | md5sum)"
  echo "=== Round $i/$MAX ($(date +%H:%M)) ==="

  timeout 90m claude -p "You are the squad lead. Follow CLAUDE.md. $SPEC_NOTE Read .mysquad/PLAN.md, .mysquad/STATUS.md, .mysquad/LEARNINGS.md. First process answered open questions (lines with ANSWER:). \
If .mysquad/PLAN.md has no tasks, use the product-owner first. Otherwise take the next batch of open tasks, \
run them through developer -> tester -> reviewer, merge what passes all gates, and update .mysquad/STATUS.md. \
Stop after one batch." \
    --model "$LEAD_MODEL" \
    --permission-mode acceptEdits \
    --max-turns 150 \
    | tee -a .mysquad/log/squad.log || echo "Round $i failed, continuing."

  OQ="$(open_questions)"; N_NEW="$(count_lines "$OQ")"
  if [ "$N_NEW" -gt "$N_OLD" ]; then
    notify "Squad round $i: $((N_NEW-N_OLD)) new open question(s), $N_NEW in total. Answer by appending '| ANSWER: ...' in .mysquad/STATUS.md. $(printf '%s' "$OQ" | tail -n $((N_NEW-N_OLD)) | cut -c1-200 | tr '\n' ' ')"
  fi
  N_OLD="$N_NEW"
  AFTER="$(git rev-parse HEAD)$(md5sum .mysquad/STATUS.md .mysquad/PLAN.md | md5sum)"
  if [ "$BEFORE" = "$AFTER" ]; then STALE=$((STALE+1)); else STALE=0; fi
  if [ "$STALE" -ge 2 ]; then
    finish "Squad stopped: no progress for 2 rounds. Open questions: $N_OLD. See .mysquad/STATUS.md." 2
  fi
done

finish "Squad reached max rounds ($MAX). Open questions: $N_OLD. See .mysquad/STATUS.md." 1
