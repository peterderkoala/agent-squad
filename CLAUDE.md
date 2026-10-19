# CLAUDE.md

This file provides guidance to Claude Code (claude.ai/code) when working with code in this repository.

## What this repo is

A Claude Code **skill** (`setup-squad`) that installs a multi-agent "squad" into a *target* repo: subagents, skills, settings, an autonomous loop script, and `.mysquad/` state files. This repo is the skill's source, not a repo that uses the squad.

- The skill lives in `setup-squad/` (install by symlinking it into `~/.claude/skills/`). The zip is a build artifact (`zip -r setup-squad.zip setup-squad`), gitignored.
- Everything under `templates/` is **payload for target repos**. In particular `templates/CLAUDE.squad.md` is the squad-lead rulebook injected into a target's `CLAUDE.md`; it does not apply to work in this repo.
- User docs: `README.md` (install, quick start) and `docs/guide.md` (full walkthrough). Update them when behaviour of the skill, roles, state-file formats or `ralph.sh` changes.

## Commands

```bash
tests/selftest.sh                                                   # installs twice into a temp repo; second run must be a no-op, verify must be ok
python3 setup-squad/scripts/setup_squad.py --check --repo <repo>    # doctor only, writes nothing
python3 setup-squad/scripts/setup_squad.py --apply --repo <repo>    # doctor + install + verify (exit 1 on verify problems)
bash -n setup-squad/templates/.mysquad/ralph.sh                     # syntax-check the loop
```

## Architecture

- `SKILL.md` — the procedure Claude follows on `/setup-squad`: doctor → consent for installs → `--apply` → `code-review-graph install/build` → `--apply` again (restores `settings.json`/`.mcp.json` entries the graph install may overwrite) → verify → hand over user-only steps (ponytail plugin, git init/commit). It must delegate to the script, not reimplement it.
- `scripts/setup_squad.py` — single-file stdlib installer. `apply()` mirrors `templates/` into the target with these rules:
  - `settings.json` and `.mcp.json`: deep-merged via `merge_json` (existing scalars win, lists unioned).
  - Other files: created if absent; existing files are never overwritten (`kept (differs)`).
  - Files in `SPECIAL` are not copied: `CLAUDE.squad.md` goes into a `<!-- squad:start -->…<!-- squad:end -->` block of the target `CLAUDE.md`; `gitignore.squad` lines are appended to `.gitignore`.
  - `*.sh` gets the exec bit. `verify()` checks JSON validity, `bash -n` on `ralph.sh`, and agent frontmatter.
  - Adding a template file needs no script change unless it requires merge/special handling.
- `templates/.claude/agents/*.md` — roles (product-owner, architect, developer, tester, reviewer) with model and tool lists in frontmatter. Keep `templates/.mysquad/team.md` in sync when changing a role.
- `templates/.claude/skills/` — `grill-squad` (interview → `SPEC.md`/`PLAN.md`) and `plan-squad` (reformat a raw plan into `PLAN.md`).
- `templates/.mysquad/ralph.sh` — outer loop: runs `claude -p` as squad lead once per round with fresh context, state carried only in `.mysquad/*.md`. Stops on `ALL DONE` as last line of `STATUS.md`, after 2 rounds without progress (HEAD + PLAN/STATUS hash unchanged), or at max rounds. Requires `code-review-graph`; switches off `main`/`master` to `squad/work`; notifies via `SQUAD_NOTIFY_CMD`.

Cross-file contracts to keep consistent when editing: `.mysquad/` file names and line formats (`Q-n … | ANSWER:`, `D-n`, `B-n`, `C-n`, gap markers `unknown`/`not given`/`(vague)`, `ALL DONE`) are shared between `CLAUDE.squad.md`, the agent files, both skills, `routing.md`, and the `awk`/`grep` parsing in `ralph.sh`.
