# AI-Assisted Engineering Workflow — project-hadur

How a Jira ticket becomes merged code. This workflow is itself a capstone
deliverable — it is what the "AI-enabled team" interview story is about.

See `decision-log.md` D-008 for the committed decision.

---

## 1. The loop

```
Jira card (Ready for Dev)
      │
      ▼
/work-ticket HADUR-nn         ── you run this in a Claude Code session in the repo
      │
      ├─ fetch ticket via Atlassian MCP
      ├─ restate acceptance criteria; STOP if the card is underspecified
      ├─ plan (surface the plan before writing code)
      ├─ branch  hadur-nn-<slug>  off main
      ├─ implement → tests → docs → focused commits
      ├─ push, open PR (templated body)
      ├─ move Jira card → In Review
      └─ spawn `code-reviewer` subagent on the diff
              │
              └─ findings fixed, or left as PR comments
      │
      ▼
GitHub Actions: cold Claude review on the PR  (Phase 2)
      │  posts inline comments, sets required status check
      ▼
GitHub "review requested"  → github.com notifications inbox (bell)
      │
      ▼
you review the PR (diff + subagent notes + CI comments) → squash-merge
      │
      ▼
merge commit smart-commit tag → Jira card → Done; branch deleted
```

---

## 2. Components

| Piece | File / mechanism | Is it code? |
|---|---|---|
| Jira connection | `.mcp.json` — Atlassian MCP server, project scope | No — JSON config |
| The build loop | `.claude/commands/work-ticket.md` | No — markdown prompt |
| Local reviewer | `.claude/agents/code-reviewer.md` — subagent, own context + model | No — markdown prompt |
| Cold reviewer | `.github/workflows/code-review.yml` — `anthropics/claude-code-action` | Yes — ~30 lines YAML |
| Notification | GitHub native "review requested" on the PR | No — a GitHub setting |
| PR creation | Claude runs `git push` + `gh pr create` — durably authorized (D-012) | No — a permission |
| Merge gate | Branch protection on `main`, admin-enforced (D-013): PR required, force-push/deletion blocked, + CI review status check (Phase 2). Claude may open PRs; only a human merges (D-012). | No — a GitHub setting |
| Jira ↔ GitHub | Smart commits (`HADUR-nn #in-review`, `#done`) or Jira's GitHub app | No — config |

**This is Claude Code configuration, not an application.** It is *not* the Managed
Agents / Claude Developer Platform product (that cookbook builds a hosted agent in
Python/TS — wrong tool here). You build these files by talking to Claude Code (or
the interactive `/agents` command for the subagent) and review them like any PR.

---

## 3. Why two review tiers

- **`code-reviewer` subagent** — runs in a fresh context window, so it is not
  primed by the implementation reasoning. But it still runs inside the repo
  session: it inherits `CLAUDE.md`, repo conventions, and whatever the main agent
  left in shared state. Treat it as a fast, high-quality first pass — a linter
  with judgment.
- **CI review (GitHub Actions)** — a genuinely separate process. It sees only the
  diff and the PR description; it never saw the conversation that produced the
  code. This is the unbiased reviewer and the authoritative gate.
- **Both are advisory.** The human merge is the gate. Branch protection enforces
  that even if a prompt misbehaves — the flow cannot merge itself.

---

## 4. Phasing

### Phase 0 — foundations (no automation)
- **[done 2026-09-03]** Branch protection on `main`, admin-enforced: PR required,
  0 approvals, conversation resolution required, linear history, force-push and
  deletion blocked. CI status check added in Phase 2. (D-013)
- **[done 2026-09-03]** `.claude/settings.json`: allow `gh pr create` / `git
  push`, deny `gh pr merge` / `git push --force`. (D-012)
- Jira project + epics + tickets with real acceptance criteria + a ticket
  template / Definition of Ready.
- Atlassian MCP connected: `claude mcp add --scope project` → `.mcp.json`
  committed.
- `code-reviewer` subagent.
- `/work-ticket` command.
- Jira ↔ GitHub linking (smart commits).

### Phase 1 — assisted loop, human-triggered
- You run `/work-ticket HADUR-nn`. The command drives the loop in §1 up to opening
  the PR + running the subagent.
- You get the GitHub review-request notification, review, merge.

### Phase 2 — CI review gate
- Add `.github/workflows/code-review.yml`: Claude review on every PR, inline
  comments, **required status check**.
- The notification now effectively means "cold review done, ready for you."

### Phase 3 — full automation (DEFERRED)
- Jira automation on "card → Ready for Dev" → webhook → `repository_dispatch` →
  the Action runs `claude -p` headless executing `work-ticket` → opens the PR.
- Everything downstream unchanged.
- **Only after Phases 1–2 have run cleanly on real tickets.** Not part of the
  5-day v1 build.

---

## 5. Ticket template / Definition of Ready

A card does not enter "Ready for Dev" without:

- **Summary** — one line, imperative.
- **Context / background** — why this exists, links to the relevant `docs/` files.
- **Acceptance criteria** — explicit, checkable. What must be true when done.
- **Definition of done** — tests added/updated, docs updated, PR opened,
  `project-status.md` updated.
- **Out of scope** — what this ticket deliberately does not do.

`/work-ticket` restates the acceptance criteria back and **stops** if the card is
underspecified — it does not produce a best-guess implementation.

---

## 6. Branch & PR conventions

Full rules in **`git-discipline.md`**. Summary: branch `hadur-nn-<short-slug>` off
`main`, never commit to `main`; Conventional Commits, atomic, smart-commit tag on
at least one; PR body = what/why · ticket link · test evidence · `code-reviewer`
findings + resolution · handoff notes; squash-merge with `HADUR-nn #done`; only a
human merges.

---

## 7. Things to get right (all endorsed in planning)

1. Never let the flow merge itself — human merge is the gate; reviews are
   advisory; admin-enforced branch protection makes it mechanical, not just a
   convention (D-012, D-013). Opening PRs *is* delegated to Claude; merging is
   not.
2. The unbiased review is the CI one (separate process, artifact only). The
   subagent reduces bias but still shares repo conventions.
3. Underspecified tickets bounce — no best-guess implementations.
4. This workflow is capstone content — keep this doc current and screenshot the
   loop for the demo.
5. Cost: headless runs + CI reviews burn tokens per ticket. Trivial at capstone
   scale; note before Phase 3.

---

## 8. Open choices

- **Atlassian MCP flavour:** official hosted remote server (OAuth, no secrets) vs
  community `mcp-atlassian` (Docker + API token). Default to the official remote
  server unless it can't do what's needed. Tracked in `open-questions.md`.
- **Notification:** confirmed GitHub-inbox only. A `Stop`-hook phone/desktop push
  was explicitly rejected.
