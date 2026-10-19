# Using the squad

This guide covers a squad from installation to a finished run. In the target repo the lead's rules are in `.claude/agents/lead.md`, each role's rules in its own agent file, and the rules shared by all roles in the `CLAUDE.md` block between `<!-- squad:start -->` and `<!-- squad:end -->`. This guide explains them from the human side.

## 1. Prerequisites

`/setup-squad check` reports the following:

| Item | Needed for | Fix |
|---|---|---|
| git repo with a commit | worktrees, `ralph.sh` | `git init`, first commit |
| `claude` CLI | the loop | install Claude Code |
| `python3` | installer | — |
| `node` | ponytail hooks | install Node.js |
| `uv` / `uvx` | starts the code-graph MCP server | `pip install uv` |
| `code-review-graph` | one shared view of the code structure; `ralph.sh` refuses to run without it | `pip install code-review-graph` |
| ponytail plugin | "minimum that works" discipline for every role | `/plugin marketplace add DietrichGebert/ponytail`, then `/plugin install ponytail@ponytail` |
| `SQUAD_NOTIFY_CMD` (optional) | push notification on new open questions | see [Notifications](#notifications) |

The doctor also lists the test, lint and build gates it found (`npm run test/lint/build`, `pytest`, `Makefile`). If there are none, the first task becomes setting them up.

## 2. Install

Run `/setup-squad` in the target repo. Claude asks once before installing missing tools, then:

1. Copies the templates. Existing files are kept, `settings.json` and `.mcp.json` are merged, and the shared squad rules go into a marked block of `CLAUDE.md`. `.mysquad/log/`, `.mysquad/stop` and `.code-review-graph/` are added to `.gitignore`.
2. Runs `code-review-graph install --platform claude-code` and `code-review-graph build`, then applies once more to restore settings the graph install may have rewritten.
3. Verifies the result and lists what only you can do (plugin install, git commit).

You can run it again at any time. A second run changes nothing.

### Upgrade

A plain run never overwrites a file that already exists, so template fixes don't reach a repo that already has the squad. Run `/setup-squad upgrade` (script: `--upgrade`) to overwrite the squad-owned files that differ: agents, the squad skills and `ralph.sh`. They are reported as `upgraded`. Your state in `.mysquad/*.md` is never touched. Local edits to an upgraded file are replaced, so review `git diff` and restore what you want to keep.

Commit `.claude/`, `.mcp.json`, `CLAUDE.md` and `.mysquad/` so the squad travels with the repo.

### What gets installed

```
CLAUDE.md                     shared squad rules block (all roles)
.mcp.json                     code-review-graph MCP server
.claude/settings.json         "agent": "lead", permissions (no push, no rm -rf, no curl, no .env reads), ponytail, env
.claude/agents/lead.md        the lead's rulebook (main thread)
.claude/agents/*.md           the five delegated roles
.claude/skills/grill-squad    interview → SPEC
.claude/skills/plan-squad     raw plan → PLAN format
.mysquad/                     squad state + ralph.sh
```

## 3. The team

| Role | Model | Does | Never does |
|---|---|---|---|
| **lead** (main session, `lead` agent) | Opus | picks batches, dispatches, merges, keeps STATUS | writes product code |
| product-owner | Opus | goal → small tasks in `PLAN.md`, fills gap markers | touches code |
| architect | Opus | design note for `needs-design` tasks, resolves blocks | writes production code |
| developer | Sonnet | one task, test-first at its seams, own worktree, commits | redesigns, edits files outside `files:` |
| tester | Sonnet | full suite + lint + build, adds missing acceptance tests | fixes production code |
| reviewer | Opus | read-only diff review, security, `/ponytail-review` | edits files |

`.claude/settings.json` sets `"agent": "lead"`, so every Claude Code session in the target repo starts as the lead. To talk to plain Claude instead, remove that line or start with another agent (`claude --agent <name>`).

To change a role, edit `.claude/agents/<role>.md` in the target repo and update `.mysquad/team.md`.

A developer works in its own git worktree, which only contains committed files. The lead therefore starts every developer prompt with `TEAM_ROOT: <main checkout>`, and the developer reads the task and its corrections from there.

## 4. Define the work

You have three options:

- **`/grill-squad`**: the most thorough. Claude interviews you in rounds of numbered questions, each with a recommended answer, covering problem, v1 slice, non-goals, stack, gates, acceptance, seams, autonomy and guardrails. After you confirm, it writes `.mysquad/SPEC.md` (the source of truth), `decisions.md` and the goal in `PLAN.md`. Use it before an unattended run, because nobody answers questions at night.
- **`/plan-squad "<plan>"`**: you already have a plan (prose, bullets, an issue list or a file path). Claude transcribes it into the task format without adding decisions. Missing fields get gap markers: `unknown`, `not given`, `(vague)`.
- **Edit the Goal line in `.mysquad/PLAN.md` by hand**: the minimum. The squad treats every assumption it makes as an open question.

Then run the product-owner once and review the plan before you start the loop:

```text
Use the product-owner subagent to break .mysquad/SPEC.md into tasks.
```

A task looks like this:

```markdown
### T-007 Add CSV export to report page
- status: todo
- needs-design: no
- depends_on: T-003
- files: src/report.py, tests/test_report.py
- seams: GET /report.csv
- acceptance:
  - Export returns one row per order with a header line
```

The fields that matter most:

- `files:` decides parallelism. The lead runs tasks in parallel only if their `files:` are disjoint and independent, with at most 3 developers, each in a git worktree.
- `seams:` names the public interface the developer tests at. A missing seam blocks the task.
- `acceptance:` must be checkable by a test.

## 5. Run

```bash
.mysquad/ralph.sh 10
```

Each round starts a fresh `claude -p --agent lead` session (`acceptEdits`, max 150 turns, 90 min timeout) that:

1. processes answered open questions,
2. runs the product-owner if there are no tasks,
3. otherwise takes one batch through developer → tester → reviewer, merges what passes, and updates `STATUS.md`.

Between rounds the script refreshes the code graph. If you start on `main`/`master`, it first switches to a new branch `squad/work`. It never pushes.

The loop stops when:

| Condition | Exit |
|---|---|
| last line of `STATUS.md` is `ALL DONE` | 0 |
| max rounds reached | 1 |
| 2 rounds without progress (no new commit, PLAN/STATUS unchanged) | 2 |
| `.mysquad/stop` exists (checked before each round and during backoff; the file is removed) | 3 |
| `SQUAD_MAX_FAILS` (default 8) failed rounds in a row | 4 |

To stop a running loop cleanly, run `touch .mysquad/stop`. The current round finishes first.

A round that fails (non-zero exit, for example a usage or rate limit) without any progress doesn't count as a round and doesn't count toward the no-progress stop. The loop waits 5, 10, 20, 40, then 60 minutes per further failure and retries, which covers a 5-hour usage window with the default of 8.

Logs are written to `.mysquad/log/squad.log` and `.mysquad/log/notify.log`.

A task is **done** when the tests are green, the linter is clean, the build passes, the reviewer says "no blocking issues", the acceptance criteria are met and `STATUS.md` is updated. A task gets at most 3 fix iterations before it is marked `blocked`. A finding that comes back after a fix round doesn't get another fix round: the lead routes it to the architect as a `repeat-rejection` block.

## 6. Your part during a run

### Open questions

On ambiguity the squad picks the safest option, keeps working, and logs it in `.mysquad/STATUS.md`:

```
## Open questions
Q-3: Should exports include cancelled orders? | assumed no | T-007
```

Answer in place by appending to the line:

```
Q-3: Should exports include cancelled orders? | assumed no | T-007 | ANSWER: yes, flagged in a status column
```

At the start of the next round the lead records the answer as a decision `D-n` in `decisions.md`, sends plan changes to the architect and removes the line.

### Blocks

If a developer can't build a task as planned, it commits a WIP and reports `BLOCKED: <category> | <evidence> | <what must be decided>`. The architect answers CORRECT, SPLIT, REJECT or ESCALATE, and the developer continues from the WIP using the correction `C-n` written into the task. After 2 blocks on the same task, a third becomes an open question for you. You only see blocks under `## Blocked` in `STATUS.md`, unless one is escalated to you.

### Notifications

```bash
export SQUAD_NOTIFY_CMD='curl -s -H "Title: Squad" -d "$1" https://ntfy.sh/your-private-topic'
```

`ralph.sh` calls this command with the message as `$1` when new open questions appear and when the loop ends.

## 7. State files

| File | Written by | Purpose |
|---|---|---|
| `SPEC.md` | `/grill-squad` | source of truth when present |
| `PLAN.md` | product-owner, architect | goal and backlog; `design:` and `correction C-n` lines live inside tasks |
| `STATUS.md` | lead, you (answers) | current batch, done, blocked, open questions, `ALL DONE` |
| `decisions.md` | lead, architect | binding decisions `D-n \| date \| decision \| reason` |
| `LEARNINGS.md` | lead | retro rules; out-of-scope ideas are parked here, never put into a diff |
| `team.md`, `routing.md` | you | roster and who handles what |

## 8. Guardrails

- Settings deny `git push`, `git reset --hard`, `git clean`, `rm -rf`, `sudo`, `curl`/`wget`, and reads of `.env*` and `secrets/`.
- The squad never works on `main` directly, never force-pushes and never deletes data.
- Scope creep is parked in `LEARNINGS.md` under Ideas.
- Ponytail never overrides input validation, error handling, security or accessibility.
