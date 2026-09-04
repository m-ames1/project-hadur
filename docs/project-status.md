# Project Status — project-hadur

**The living handoff file.** Every work session updates this at the end: what
changed, what's next, any gotchas. A cold session reads this first.

---

## Current state

- **Phase:** Planning captured; agentic-workflow + git discipline being set up.
  Pipeline build not started.
- **As of:** 2026-09-04
- **Version:** none tagged yet (target first tag: `v0.0.0` on Day 1)
- **Merged:** PR #1 (`docs/planning-capture` — planning docs + D-012/D-013),
  PR #2 (`chore/claude-pr-permissions` — `.claude/settings.json`). `main` at
  `bf22d42`.
- **Open PRs (both branched from `main`, independent):**
  - `docs/git-discipline` — `git-discipline.md` + D-014 + CLAUDE.md/workflow
    pointers
  - `chore/branch-cleanup-hook` — `SessionStart` hook implementing D-014

## What exists

- `docs/` set: `handoff-brief.md`, `decision-log.md` (D-001..D-014),
  `architecture.md`, `ai-assisted-workflow.md`, `git-discipline.md`,
  `project-plan.md`, this file, `open-questions.md`.
- `CLAUDE.md` router at repo root.
- `.claude/settings.json`: allow `gh pr create` / `git push`, deny `gh pr merge`
  / `git push --force` (D-012). *(merged)*
- `gh` CLI installed and authenticated (account `m-ames1`, scopes
  `repo, read:org, gist` — no `workflow` scope yet; needed in Phase 2).
- **Branch protection on `main`**, admin-enforced (D-013): PR required, 0
  approvals, conversation resolution + linear history required, force-push and
  deletion blocked. No status checks yet. *(live)*
- `origin` remote on **HTTPS** for fetch + push (repo-local), creds via `gh`
  token; `fetch.prune = true`. SSH unusable from the Claude Code sandbox.
- `SessionStart` branch-cleanup + `main` fast-forward hook — *spec'd (D-014),
  on branch `chore/branch-cleanup-hook`, not merged; not active until merged +
  a new session starts.*
- Personal notes in `supporting-files/` (gitignored).
- No pipeline code, no `.claude/` agents or commands, no `.mcp.json` (Jira), no
  Docker, no Jira project, no Airflow, no synthetic data.

## Next action

1. User reviews and merges the two open PRs (`docs/git-discipline`,
   `chore/branch-cleanup-hook`) on github.com.
2. After merge: start a fresh Claude Code session — the new hook will
   `git fetch`, prune merged local branches, and fast-forward `main`
   automatically. (Also loads any `.claude/settings.json` changes.)
3. Begin **Day 1** of `project-plan.md` (repo scaffold + rest of the agentic
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
| 2026-09-04 | User merged PR #1 + #2. Synced `main` to `bf22d42`, deleted the two merged local branches (SHA-verified). Switched `origin` to HTTPS (fetch was SSH, unusable in sandbox). Wrote `git-discipline.md`, logged D-014 (branch-cleanup + `main` ff hook), built the hook; split docs vs. implementation into two branches. | PRs open: `docs/git-discipline`, `chore/branch-cleanup-hook`. Awaiting human review + merge. |
