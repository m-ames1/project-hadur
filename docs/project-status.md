# Project Status — project-hadur

**The living handoff file.** Every work session updates this at the end: what
changed, what's next, any gotchas. A cold session reads this first.

---

## Current state

- **Phase:** Planning captured; agentic-workflow setup partly done. Pipeline
  build not started.
- **As of:** 2026-09-03
- **Version:** none tagged yet (target first tag: `v0.0.0` on Day 1)
- **Open PRs (both branched from `main`, independent):**
  - `docs/planning-capture` — planning docs + D-012/D-013 decision records
  - `chore/claude-pr-permissions` — `.claude/settings.json` PR permissions

## What exists

- `docs/` planning set: `handoff-brief.md`, `decision-log.md` (D-001..D-013),
  `architecture.md`, `ai-assisted-workflow.md`, `project-plan.md`, this file,
  `open-questions.md`.
- `CLAUDE.md` router at repo root.
- `gh` CLI installed and authenticated (account `m-ames1`, scopes
  `repo, read:org, gist` — no `workflow` scope yet; needed in Phase 2).
- **Branch protection on `main`**, admin-enforced (D-013): PR required, 0
  approvals, conversation resolution + linear history required, force-push and
  deletion blocked. No status checks yet. *(applied server-side; live now)*
- `.claude/settings.json`: allow `gh pr create` / `git push`, deny `gh pr merge`
  / `git push --force` (D-012). *(on branch `chore/claude-pr-permissions`, PR
  open, not yet merged)*
- Personal notes in `supporting-files/` (gitignored).
- No pipeline code, no `.claude/` agents or commands, no `.mcp.json` (Jira), no
  Docker, no Jira project, no Airflow, no synthetic data.

## Next action

1. User reviews and merges the two open PRs (`docs/planning-capture`,
   `chore/claude-pr-permissions`) on github.com.
2. After merge, `git checkout main && git pull` locally.
3. Restart the Claude Code session so `.claude/settings.json` takes effect.
4. Begin **Day 1** of `project-plan.md` (repo scaffold + rest of the agentic
   workflow foundation: `.mcp.json`, `code-reviewer` subagent, `/work-ticket`).

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
