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
| Local reviewer | `.claude/agents/code-reviewer.md` — subagent, own context + model. **v1 uses this.** | No — markdown prompt |
| GitHub Actions review job | `.github/workflows/code-review.yml` — `anthropics/claude-code-action`. **Deferred to Phase 2 (D-016).** | Yes — ~30 lines YAML |
| Notification | GitHub native "review requested" on the PR | No — a GitHub setting |
| PR creation | Claude runs `git push` + `gh pr create` — durably authorized (D-012) | No — a permission |
| Merge gate | Branch protection on `main`, admin-enforced (D-013): PR required, force-push/deletion blocked, + the GitHub Actions review status check once added (Phase 2). Claude may open PRs; only a human merges (D-012). | No — a GitHub setting |
| Jira ↔ GitHub | Smart commits (`HADUR-nn #in-review`, `#done`) or Jira's GitHub app | No — config |

**This is Claude Code configuration, not an application.** It is *not* the Managed
Agents / Claude Developer Platform product (that cookbook builds a hosted agent in
Python/TS — wrong tool here). You build these files by talking to Claude Code (or
the interactive `/agents` command for the subagent) and review them like any PR.

---

## 3. Agent topology and specialization

Decision record: `decision-log.md` **D-015**.

### The agent set

The workflow uses a deliberately small set of agents. Boundaries are drawn only
where **context or bias isolation requires them** — never by task category,
technology, or pipeline layer.

| Agent | Role | Why it is separate |
|---|---|---|
| **Implementer** | The main Claude Code session, driven by `/work-ticket`. Holds full repo context (`CLAUDE.md`, `docs/`, the ticket). All `feat` / `fix` / `chore` / `docs` work runs here. | Not a defined subagent — it is the session. One implementer. |
| **`code-reviewer` subagent** (`.claude/agents/code-reviewer.md`) | Pre-flight review of the diff, before the PR is opened. **v1 uses this.** | Runs in its own context window — it never sees the parent session's reasoning. It still reads `CLAUDE.md` and the parent's handoff prompt, so keep that prompt minimal ("review this diff against this ticket"). A fast first pass, not the final word. |
| **GitHub Actions review job** (`.github/workflows/code-review.yml`) | A merge-gating review after the PR opens; produces a required status check + audit trail. **Deferred — Phase 2 (D-016).** | Runs on GitHub's servers, on a clean checkout, with a fixed neutral prompt — structurally impossible to prime. It is a job inside CI, not "CI" itself. |

Both automated reviewers are advisory. The human review on the PR is itself an
independent cold pass, and the human merge is the gate; branch protection (D-013)
enforces that the flow cannot merge itself.

A planning/architect subagent (epic → tickets) may be added later if that work
grows. It is not part of the initial set.

### The two review layers — and why v1 uses only the subagent

Decision record: **D-016**.

The subagent and the GitHub Actions job are **not** "biased vs. unbiased" — the
subagent runs in a separate context window and never sees how the code was
reasoned about. They do **different jobs at different moments**:

| | `code-reviewer` subagent | GitHub Actions review job |
|---|---|---|
| **When** | before the PR exists | after every push to the PR |
| **Where** | your machine, in the session | GitHub's servers, clean checkout |
| **Purpose** | improve the artifact before a human sees it; implementer fixes findings in the same session, no round-trip | *guarantee* every PR got an independent look; block merge via a status check; leave an audit trail |
| **Priming risk** | low, and controllable (minimal handoff prompt) | none — no per-PR prompt is authored |

Both use the same model, so neither catches a systematic model blind spot the
other would.

**v1 uses the subagent only**, because:
- The human review on the PR is already an independent cold pass before merge.
- The subagent adds value immediately for free (one markdown file): cleaner PRs,
  faster iteration.
- The GitHub Actions job largely duplicates the careful human review, at real
  cost — an API-key secret, the `workflow` OAuth scope, tokens per run, another
  moving part.
- Its distinct payoff — an enforced, auditable "every PR is automatically gated"
  story — matters for a team or an interview narrative, not for shipping the
  5-day v1.

**Add the GitHub Actions job** when that enforced gate is worth the setup. It is
a one-file addition (`.github/workflows/code-review.yml` +
`anthropics/claude-code-action`) plus the `ANTHROPIC_API_KEY` secret and the
`workflow` scope. Tracked as Phase 2 below.

### Why not per-domain agents

A separate agent is justified only when it must *not* share the main session's
context. "Chore vs docs", "Bronze vs Silver vs Gold", and "Airflow vs dbt vs
Snowflake" are labels, not structural boundaries — the same conventions, repo,
and context apply to all of them. Per-domain agents would duplicate most of their
instructions, drift out of sync with each other and with `CLAUDE.md`, and add
cold-start and orchestration cost with no behavioural gain — a poor trade on a
solo, time-boxed build.

### Where specialization goes instead

| Concern | Mechanism |
|---|---|
| **Domain rules** (Bronze/Silver/Gold responsibilities, layer contracts) | Documentation. `architecture.md` today; a dedicated conventions doc if depth is needed. The implementer reads the section the ticket points to. |
| **Repeatable procedures** (e.g. "how an Airflow task is written in this repo") | A `.claude/skills/` skill the implementer loads when relevant — added once repetition justifies it, not up front. |
| **Per-task instruction** ("this is a Bronze task, here are the rules") | The ticket: acceptance criteria plus links to the relevant `docs/` sections. |
| **Output category** | The Conventional Commit type (`feat` / `fix` / `chore` / `docs`). It labels the change; it is not a reason for a different worker. |

The result: intelligence concentrates in tickets and docs — versioned, reviewable,
shared — rather than in a set of agent prompts that must be kept mutually
consistent.

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
