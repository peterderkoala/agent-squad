# CLAUDE.md

This file provides guidance to Claude Code (claude.ai/code) when working with code in this repository.

## What this repo is

A Claude Code **skill** (`setup-squad`) that installs a multi-agent "squad" into a *target* repo: subagents, skills, settings, an autonomous loop script, and `.mysquad/` state files. This repo is the skill's source, not a repo that uses the squad.

- The skill lives in `setup-squad/` (install by symlinking it into `~/.claude/skills/`). The zip is a build artifact (`zip -r setup-squad.zip setup-squad`), gitignored.
- Everything under `templates/` is **payload for target repos**; none of it applies to work in this repo. `templates/.claude/agents/lead.md` is the lead's rulebook (main-thread agent via `"agent": "lead"` in the template settings); `templates/CLAUDE.squad.md` holds only rules shared by all roles, because subagents load `CLAUDE.md` too.
- User docs: `README.md` (install, quick start) and `docs/guide.md` (full walkthrough). Update them when behaviour of the skill, roles, state-file formats or `ralph.sh` changes.

## Commands

```bash
tests/selftest.sh                                                   # idempotent apply, --upgrade keeps state, ralph.sh stop/failure exits (fake claude)
python3 setup-squad/scripts/setup_squad.py --check --repo <repo>    # doctor only, writes nothing
python3 setup-squad/scripts/setup_squad.py --apply --repo <repo>    # doctor + install + verify (exit 1 on verify problems)
python3 setup-squad/scripts/setup_squad.py --upgrade --repo <repo>  # also overwrite squad-owned files that differ
bash -n setup-squad/templates/.mysquad/ralph.sh                     # syntax-check the loop
```

## Architecture

- `SKILL.md` — the procedure Claude follows on `/setup-squad`: doctor → consent for installs → `--apply` → `code-review-graph install/build` → `--apply` again (restores `settings.json`/`.mcp.json` entries the graph install may overwrite) → verify → hand over user-only steps (ponytail plugin, git init/commit). It must delegate to the script, not reimplement it.
- `scripts/setup_squad.py` — single-file stdlib installer. `apply()` mirrors `templates/` into the target with these rules:
  - `settings.json` and `.mcp.json`: deep-merged via `merge_json` (existing scalars win, lists unioned).
  - Other files: created if absent; existing ones are kept (`kept (differs)`), except with `--upgrade`, which overwrites them unless `is_state()` (`.mysquad/*.md`).
  - Files in `SPECIAL` are not copied: `CLAUDE.squad.md` goes into a `<!-- squad:start -->…<!-- squad:end -->` block of the target `CLAUDE.md`; `gitignore.squad` lines are appended to `.gitignore`.
  - `*.sh` gets the exec bit. `verify()` checks JSON validity, `bash -n` on `ralph.sh`, and agent frontmatter.
  - Adding a template file needs no script change unless it requires merge/special handling.
- `templates/.claude/agents/*.md` — lead plus the five delegated roles, with model and tool lists in frontmatter. Keep `templates/.mysquad/team.md` in sync when changing a role. The developer runs in a worktree and reads `.mysquad/` from the `TEAM_ROOT` the lead passes, since uncommitted plan changes are invisible in the worktree.
- `templates/.claude/skills/` — `grill-squad` (interview → `SPEC.md`/`PLAN.md`) and `plan-squad` (reformat a raw plan into `PLAN.md`).
- `templates/.mysquad/ralph.sh` — outer loop: runs `claude -p --agent lead` once per round with fresh context, state carried only in `.mysquad/*.md`. Exits 0 on an exact `ALL DONE` last line of `STATUS.md`, 1 at max rounds, 2 after 2 successful rounds without progress (HEAD + PLAN/STATUS hash unchanged), 3 on `.mysquad/stop`, 4 after `SQUAD_MAX_FAILS` failed rounds in a row (failed rounds without progress back off 5→60 min and don't count as rounds). Requires `code-review-graph`; switches off `main`/`master` to `squad/work`; notifies via `SQUAD_NOTIFY_CMD`.

Cross-file contracts to keep consistent when editing: `.mysquad/` file names and line formats (`Q-n … | ANSWER:`, `D-n`, `B-n`, `C-n`, gap markers `unknown`/`not given`/`(vague)`, `ALL DONE`) are shared between `CLAUDE.squad.md`, the agent files, both skills, `routing.md`, and the `awk`/`grep` parsing in `ralph.sh`.
