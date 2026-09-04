# Project Status — project-hadur

**The living handoff file.** Every work session updates this at the end: what
changed, what's next, any gotchas. A cold session reads this first.

---

## Current state

- **Phase:** Planning + agentic-workflow + git discipline done. Pipeline build
  not started.
- **As of:** 2026-09-04
- **Version:** none tagged yet (target first tag: `v0.0.0` on Day 1)
- **Merged:** PR #1–#4. `main` at `83dc250`. No open PRs. Only `main` exists
  locally (branch-cleanup hook pruned the rest).

## What exists

- `docs/` set: `handoff-brief.md`, `decision-log.md` (D-001..D-017),
  `architecture.md`, `ai-assisted-workflow.md`, `git-discipline.md`,
  `project-plan.md`, this file, `open-questions.md`.
- **v1 platform pivoted to Airflow + dbt + Snowflake (D-017)**, superseding
  D-004 (Parquet between layers), D-005 (Postgres delivery table), and D-006
  (PySpark/pandas engine boundary). DuckDB is the local dev/CI warehouse;
  Snowflake is the Day 5 demo target. `architecture.md`, `project-plan.md`,
  `open-questions.md`, `CLAUDE.md`, and `handoff-brief.md` are rewritten to
  match. Days 1–5 are not yet built — this is still a docs-only pivot.
- `CLAUDE.md` router at repo root.
- `.claude/settings.json`: allow `gh pr create` / `git push`, deny `gh pr merge`
  / `git push --force` (D-012). Plus a `SessionStart` hook (see below).
- `gh` CLI installed and authenticated (account `m-ames1`, scopes
  `repo, read:org, gist` — no `workflow` scope yet; needed in Phase 2).
- **Branch protection on `main`**, admin-enforced (D-013): PR required, 0
  approvals, conversation resolution + linear history required, force-push and
  deletion blocked. No status checks yet. *(live)*
- `origin` remote on **HTTPS** for fetch + push (repo-local), creds via `gh`
  token; `fetch.prune = true`. SSH unusable from the Claude Code sandbox.
- **`SessionStart` hook** (`.claude/hooks/prune-merged-branches.sh`, D-014):
  *live and verified*. Each session start it deletes local branches whose PR
  merged into `main` (API + SHA-matched) and fast-forwards `main`. Opt-out:
  `git config hadur.autoUpdateMain false` / `.git/NO_AUTO_MAIN`.
- Personal notes in `supporting-files/` (gitignored).
- No pipeline code, no `.claude/` agents or commands, no `.mcp.json` (Jira), no
  Docker, no Jira project, no Airflow, no synthetic data.

## Next action

**Begin Day 1** of `project-plan.md`: repo scaffold (pyenv + Python 3.12,
`pyproject.toml`, `VERSION` `0.0.0`, `CHANGELOG.md`, real README) + the rest of
the agentic-workflow foundation — Atlassian MCP `.mcp.json`, `code-reviewer`
subagent, `/work-ticket` command, Jira project + tickets — plus the Day 1 dbt
scaffold (dbt-core + dbt-duckdb + dbt-snowflake + dbt_utils, `dbt debug` green
on `duckdb`) — then tag `v0.0.0`.

The delivery mechanism (branch protection, PR permissions, git-discipline doc,
branch-cleanup hook) is done; Day 1 builds on it.

## Open questions blocking work

None blocking. See `open-questions.md` for choices to make during the build
(engine, supporting table, MCP flavour, DQ thresholds, customer identity).

## Gotchas / notes for the next session

- Commit only when the user explicitly says so, in the moment. Same for push.
- `supporting-files/` is gitignored on purpose — personal notes, not repo content.
- This project's rhythm is decide-now / execute-later; don't start build work
  without an explicit go.

---

## Session log

| Date | Session did | Left it at |
|---|---|---|
| 2026-09-03 | Captured the planning conversation into `docs/` + `CLAUDE.md` | Committed at `64802cc` on `docs/planning-capture` |
| 2026-09-03 | Installed + authed `gh`; applied admin-enforced branch protection on `main` (D-013); logged D-012/D-013; split remaining changes into two independent branches off `main` and opened a PR for each | PRs open: `docs/planning-capture` (docs + decisions), `chore/claude-pr-permissions` (`.claude/settings.json`). Awaiting human review + merge. |
| 2026-09-04 | User merged PR #1 + #2. Synced `main` to `bf22d42`, deleted the two merged local branches (SHA-verified). Switched `origin` to HTTPS (fetch was SSH, unusable in sandbox). Wrote `git-discipline.md`, logged D-014 (branch-cleanup + `main` ff hook), built the hook; split docs vs. implementation into two branches. | PRs open: `docs/git-discipline`, `chore/branch-cleanup-hook`. Awaiting human review + merge. |
| 2026-09-04 | User merged PR #3 + #4. Bootstrapped the hook (`git checkout main && git pull`); a fresh session then ran it — pruned both feature branches, `main` at `83dc250`. Hook confirmed working end to end. | Workflow foundation complete. Next: Day 1. This PR refreshes the status doc. |
| 2026-09-04 | Pivoted v1 platform to Airflow + dbt + Snowflake (D-017); superseded D-004/D-005/D-006; rewrote architecture, plan, open-questions, CLAUDE.md, handoff-brief | PR open, awaiting human merge |
