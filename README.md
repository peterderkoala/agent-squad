# agent-squad

A Claude Code skill that turns any git repo into a small, autonomous dev team. The main Claude session becomes the **tech lead** and delegates to five subagents: product-owner, architect, developer, tester and reviewer. A loop script (`ralph.sh`) runs the squad round after round with fresh context. All state lives in markdown files under `.mysquad/`, so you can read, edit and commit it.

```
goal ──► /grill-squad ──► SPEC.md ──► product-owner ──► PLAN.md
                                                          │
             ┌────────────── ralph.sh, one batch per round ┘
             ▼
   developer (worktree, test-first) ──► tester ──► reviewer ──► merge
             ▲                                │
             └──── fix / block ◄── architect ◄┘
```

## Install the skill

Requires Claude Code. Pick one:

```bash
# Maintainer: symlink, so edits in this repo are live
ln -s "$PWD/setup-squad" ~/.claude/skills/setup-squad

# User: copy
cp -r setup-squad ~/.claude/skills/

# claude.ai / sharing: build the zip
zip -r setup-squad.zip setup-squad -x '*/__pycache__/*'
```

## Quick start

In the target repo (it needs a git repo with at least one commit):

```text
/setup-squad check        # doctor only, writes nothing
/setup-squad              # install: agents, skills, settings, .mysquad/, CLAUDE.md block
/grill-squad              # interview → .mysquad/SPEC.md + goal   (or: /plan-squad "<your plan>")
```

Then ask the product-owner subagent to fill `.mysquad/PLAN.md`, review that plan, and start the loop:

```bash
.mysquad/ralph.sh 10      # up to 10 rounds
```

Answer open questions by appending `| ANSWER: <text>` to the line in `.mysquad/STATUS.md`. The full walkthrough is in **[docs/guide.md](docs/guide.md)**.

## Repository layout

| Path | What it is |
|---|---|
| `setup-squad/SKILL.md` | The `/setup-squad` procedure Claude follows |
| `setup-squad/scripts/setup_squad.py` | Doctor and idempotent installer (stdlib only) |
| `setup-squad/templates/` | Everything copied into a target repo |
| `tests/selftest.sh` | Installs into a temp repo twice and checks that the second run is a no-op |
| `docs/guide.md` | How to use the squad |

## Developing

```bash
tests/selftest.sh                                                     # must print PASS
python3 setup-squad/scripts/setup_squad.py --check --repo <repo>      # doctor
python3 setup-squad/scripts/setup_squad.py --apply --repo <repo>      # install/merge
```

Existing files in a target repo are never overwritten. A changed template only reaches repos that don't have that file yet. The exceptions are `settings.json` and `.mcp.json` (deep-merged) and the `CLAUDE.md` squad block (replaced between its markers).

## License

See [LICENSE](LICENSE).
