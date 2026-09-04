# Decision Log — project-hadur

Dated decision records with rationale. Newest decisions are appended; existing
records are not rewritten (add a superseding record instead). Graduated from
`supporting-files/build-standards-and-decisions.md` and the 2026-09-03 planning
conversation.

Status values: **Committed** (acting on it) · **Superseded** · **Open**.

---

## D-001 — Two-era platform: Airflow v1 → Databricks v2 migration

- **Date:** 2026-09-01 · **Status:** Committed

**Context.** The original plan was "local PySpark Bronze/Silver/Gold, then move to
Databricks DLT." A stronger alternative surfaced: build a real Airflow-orchestrated
platform first as v1, then migrate it to Databricks as v2.

**Decision.** Capstone **v1 is the Airflow-orchestrated platform**, built end to
end first. The Databricks/Lakeflow rebuild is **v2**, done as a migration off the
working v1. The simpler "local → Databricks directly, no Airflow" path is rejected.

**Rationale.** Forces articulating the real boundary between *orchestration* (DAGs,
task dependencies, retries, backfills) and *declarative pipeline semantics*
(Lakeflow table dependencies, expectations, incremental processing) — a sharper
interview story than "wrote it locally then moved it to the cloud." Aligns with
target roles that require Airflow / Cloud Composer.

**Consequences.** Two platforms to build → real ballooning risk. Airflow is kept
deliberately minimal (see D-003). The migration analysis is the payoff, not
Airflow production-ops mastery. Era git tags: `airflow-platform-v1`,
`databricks-platform-v2`.

**Supersedes.** The 2026-08-28 "daily hands-on Databricks, clean data first"
decision. Databricks work now waits until Airflow v1 exists.

---

## D-002 — 5-day v1 scope: transactional pipeline only

- **Date:** 2026-09-03 · **Status:** Committed

**Decision.** The 5-day v1 build is: one Airflow DAG for the **transactional
supplier-data pipeline**, Bronze → Silver → Gold, dirty-data cleaning, a DQ check
gating Gold, and a join to one supporting/entity table in Gold. Nothing else.

**Excluded from v1.** Reference-data pipeline, analytics pipeline as a separate
DAG, any cloud infrastructure, Databricks.

**Rationale.** Five days is a hard limit. A single coherent end-to-end slice that
actually runs beats broader coverage that doesn't.

---

## D-003 — Airflow runs locally via a trimmed docker-compose

- **Date:** 2026-09-03 · **Status:** Committed

**Decision.** Run Airflow locally using the official `docker-compose.yaml`,
trimmed: webserver + scheduler + Postgres, **LocalExecutor**, Flower removed,
`AIRFLOW__CORE__LOAD_EXAMPLES=false`. Not `airflow standalone` (SQLite +
SequentialExecutor).

**Rationale.** Costs ~1 afternoon (copy-paste from docs), and pays off three
times: real Airflow UI screenshots, parallel task execution (better story than
SequentialExecutor), and the v2 migration mapping (`Docker/config deployment →
Databricks Asset Bundles`) needs the Docker piece to exist. No Celery/k8s
executor, no HA — that would be production-ops scope with no payoff here.

---

## D-004 — Parquet between layers in v1; Delta in v2

- **Date:** 2026-09-03 · **Status:** Committed

**Decision.** Bronze, Silver, and Gold storage is **Parquet** in v1 (partitioned
by ingest date / run id), becoming **Delta tables** in Unity Catalog in v2. Raw
provider inputs stay CSV/JSON/TXT in both eras. Never use CSV between layers.

**Rationale.** Delta *is* Parquet plus a transaction log. Speaking Parquet in v1
makes the v2 upgrade a swap (gain ACID, time travel, schema enforcement, `MERGE`)
rather than a rewrite. CSV between layers loses types and schema and can't be the
on-ramp to Delta.

---

## D-005 — Gold delivers a Postgres table, not CSV files

- **Date:** 2026-09-03 · **Status:** Committed

**Context.** Earlier framing was "the customer always gets CSV." Corrected:
CSV-over-SFTP is one common external pattern, but warehouse-to-warehouse **table**
delivery is at least as common now and more production-shaped.

**Decision.** v1 Gold delivery target is a **Postgres table**, reusing the
Postgres already running in the Airflow docker-compose (dedicated database or
schema as the "delivery warehouse"). `gold_publish` loads
`delivery.<customer>_<dataset>`. A Parquet copy and a CSV extract are kept as
secondary audit artifacts. A `delivery_log` table records each run
(row count, checksum, run id, timestamp); a `data_dictionary` table documents
columns.

**v2 mapping.** `gold_publish` is the one task that changes — Postgres load
becomes a managed Delta table in `prod_catalog.gold`; consumption becomes a SQL
warehouse query or Delta Sharing. Near-zero-diff on Gold columns / business key.

---

## D-006 — Engine-agnostic transform boundary; PySpark local with pandas fallback

- **Date:** 2026-09-03 · **Status:** Committed

**Decision.** Transform functions take an input path and output path, operate on a
DataFrame, and write Parquet — engine-agnostic at the boundary. Use **PySpark
local mode**. Fall back to **pandas / polars** without hesitation if
Spark-in-Docker (custom image with Java + pyspark) costs more than half a day.

**Rationale.** Spark is the v2 headline; v1 doesn't need to prove it. The Parquet
contract makes the engine swappable, and that swappability is itself a design
point for the v2 story. Do not spend Day 1–2 fighting a JVM in Docker.

---

## D-007 — Claude Code only for v1; no Codex / AGENTS.md

- **Date:** 2026-09-03 · **Status:** Committed

**Decision.** v1 uses Claude Code exclusively. No Codex integration, no
`AGENTS.md`. Recorded as a deliberate scope cut, not an omission.

**Rationale.** One target employer specifically uses Claude Code. Skipping Codex
removes a whole documentation/config surface on a 5-day timeline. Adding
`AGENTS.md` later is a ~10-minute file copy.

---

## D-008 — Human-gated agent loop; two-tier code review

- **Date:** 2026-09-03 · **Status:** Committed

**Decision.** Tickets are built by Claude Code on a branch and opened as PRs.
Review is two-tier: (1) a `code-reviewer` **subagent** — fast, local, fresh
context — as a first pass; (2) a **Claude review in GitHub Actions CI** — a cold
separate process that sees only the diff and PR description — as the authoritative
gate (required status check). Both are advisory; **the human merge is the gate**.
Branch protection on `main` enforces this. Notification is GitHub's "review
requested" in the github.com notifications inbox — no email, no phone.

**Rationale.** A subagent in the same session still inherits repo conventions and
`CLAUDE.md`; the genuinely unbiased reviewer is the CI process that never saw the
implementation reasoning. Underspecified tickets must bounce rather than get a
best-guess implementation.

---

## D-009 — SemVer from 0.0.0 (Theseus precedent)

- **Date:** 2026-09-03 (standard predates, from prior work) · **Status:** Committed

**Decision.** Real Semantic Versioning from `0.0.0`. `VERSION` file + git tags +
`CHANGELOG.md`. Stay in `0.x` while pre-first-full-slice. PATCH = behavior-
preserving fix; MINOR = backward-compatible new capability; MAJOR only at 1.0+ for
a broken pipeline contract. Era tags `airflow-platform-v1` /
`databricks-platform-v2`.

**Rationale.** Mirrors the versioning discipline used on Theseus. The tag/commit
history becomes a concrete artifact of the project's evolution.

---

## D-010 — Reference codes kept as a static lookup, not a pipeline

- **Date:** 2026-09-03 · **Status:** Committed

**Decision.** `reference_codes.csv` is a static lookup file. Silver validates
transactional records against it (invalid codes → quarantine) and enriches from
it. No ingestion DAG, no slowly-changing-dimension handling in v1.

**Rationale.** Shows reference-code handling — one of the target "realistic
quality issues" — without the cost of a second pipeline on a 5-day timeline.

---

## D-011 — Do not split suppliers into separate repos yet (Theseus precedent)

- **Date:** 2026-09-03 (predates, from prior work) · **Status:** Committed

**Decision.** One provider / one customer → single repo. Keep supplier-specific
logic isolated under `src/` so a future extraction is natural. Do not split now.

**Rationale.** Splitting now would be premature. The isolation makes "extract a
supplier into its own repo" a demonstrable next step (the real Theseus
evolution), triggered if synthetic providers are added later.

---

## D-012 — PR authority: Claude Code opens PRs, humans always merge

- **Date:** 2026-09-03 · **Status:** Committed

**Context.** Setting up the agentic workflow (D-008): Claude Code builds tickets
on branches and needs a way to surface finished work. The question was whether
Claude should be able to (a) open PRs and (b) merge PRs on the remote.

**Decision.**
- **Claude Code may open PRs** on the remote (`gh pr create`, after pushing a
  feature branch). Durably authorized — no per-PR human approval needed.
- **Claude Code must never merge PRs.** Every merge to `main` is a human action,
  performed on github.com. No carve-out for "trivial" PRs.

**Rationale.**
- Opening a PR changes nothing protected, is trivially reversible (close it), and
  is the mechanism that triggers CI, review, and the notification. Making a human
  open every PR is friction with no safety gain — the diff is still reviewed
  before merge either way.
- Merging is the gate. If Claude could merge, it would effectively be approving
  its own work — the exact self-bias the separate CI reviewer (D-008) exists to
  avoid. Both review layers are advisory; the human merge is what makes them mean
  something, and the merge click is the forcing function that makes the human
  actually read the diff.

**Caveats.**
- **Solo repo.** On a multi-person repo, an agent opening PRs freely creates
  review noise, muddies authorship, and can trip CI on half-formed work — there
  you'd want PRs opened deliberately or clearly bot-labeled. Revisit if a second
  contributor joins.
- **Public repo.** PRs here show in public activity. Fine for a portfolio piece;
  a reason to keep PR bodies clean.

**Enforcement.** D-013 (branch protection) is the server-side layer.
`.claude/settings.json` allows `gh pr create` / `git push` and explicitly denies
`gh pr merge`.

---

## D-013 — Branch protection on `main`, admin-enforced

- **Date:** 2026-09-03 · **Status:** Committed

**Decision.** Classic branch protection on `main`:
- Require a pull request before merging (**0 required approvals** — solo repo;
  GitHub forbids self-approval, so requiring 1 would make own PRs unmergeable)
- **Enforce for administrators** — the rule applies to the repo owner too
- Require conversation resolution before merge
- Require linear history (squash / rebase only)
- Block force pushes; block branch deletion
- Required status checks: none yet — add the CI review check in Phase 2

**Rationale.**
- **Layer 2, server-side.** Claude Code runs `git` / `gh` with the owner's
  credentials, so `.claude/settings.json` permissions alone (layer 1) don't bind
  it if misconfigured. Admin-enforced branch protection is enforced by GitHub
  regardless of local config, so "Claude never pushes to or merges `main`"
  becomes a mechanical fact rather than a matter of discipline.
- **Forces the intended workflow** — ticket → branch → PR → review → human merge.
  No accidental shortcut.
- **Protects the artifact** — `main` always reflects reviewed, intentional state;
  history can't be rewritten and the branch can't be deleted.
- **Capstone content** — admin-enforced branch protection with required review
  resolution is a concrete engineering-discipline talking point.

**Tradeoff.** The owner also goes through PRs now; merges happen via the GitHub UI,
not `git push`. Emergency bypass = toggle admin enforcement off, act, toggle back.
The friction is intended.

**Reusability.** A good default for any new project repo, not only this one.
Captured as a cross-project preference in the user's personal memory so it carries
forward to future repos.

**Applied.** 2026-09-03 via `gh api --method PUT
repos/m-ames1/project-hadur/branches/main/protection`.

---

## D-014 — Automated local branch cleanup + `main` fast-forward (SessionStart hook)

- **Date:** 2026-09-04 · **Status:** Committed

**Context.** After merging PRs on github.com, local branches linger and local
`main` goes stale. GitHub is set to auto-delete head branches on merge, and
`fetch.prune=true` clears stale `origin/*` refs — but neither removes the *local*
branch or advances local `main`.

**Decision.** A `SessionStart` hook
(`.claude/hooks/prune-merged-branches.sh`, wired in `.claude/settings.json`) runs
at the start of every Claude Code session and performs exactly two guarded
mutations.

**1. Delete a local branch — merged-PR-only.** Local branch `B` is deleted **iff
all four hold**:
1. A PR exists with head `B`, base `main`, state `MERGED` (`mergedAt` non-null,
   `mergeCommit` present), confirmed via the GitHub API (`gh`) — not git's local
   merge detection.
2. `B`'s local tip SHA equals that PR's `headRefOid` (the exact merged commit) —
   proves nothing local is lost.
3. `B` is not `main`.
4. `B` is not the currently checked-out branch.

Never a trigger: `origin/B` gone; PR `CLOSED`; no PR; `git branch --merged`
ancestry; force-pushed remote. Any failure → skip + log the reason.

**2. Fast-forward local `main`.** After `git fetch --prune`, advance local `main`
to `origin/main` **only on a clean fast-forward** — ref-only move when on another
branch (working tree untouched), `merge --ff-only` when `main` is checked out.
Never a merge commit, force, or rebase; never touches feature branches. Not
fast-forwardable → leave alone + log. **Opt-out** for `git bisect` / pinning:
`git config hadur.autoUpdateMain false` or a `.git/NO_AUTO_MAIN` sentinel.

**Fail-safe.** Not a git repo, `gh` missing/unauthenticated, or offline → do
nothing, exit 0. The hook can never block or error a session. Prints only when it
acts.

**Rationale.** Keeps the local branch list and `main` honest with zero risk: the
only cause of a branch deletion is a confirmed merge, verified by SHA; the only
change to `main` is a fast-forward. Mirrors team tooling (`gh-poi`,
`git-delete-merged-branches`) where merge status is the sole trigger. The
`main` fast-forward is the lower-value half — after `fetch`, `origin/main` is
already current for rebasing — but it's safe and removes the "branched from stale
`main`" footgun.

**Implementation.** Docs (this record + `git-discipline.md` §6) on
`docs/git-discipline`; the hook + `.claude/settings.json` wiring on
`chore/branch-cleanup-hook` — decision and implementation as separate concerns
(D-012/D-013 precedent).

---

## D-015 — Agent topology: minimal, isolation-driven

- **Date:** 2026-09-04 · **Status:** Committed

**Decision.** The AI-assisted workflow uses a deliberately small set of agents.
Agent boundaries are drawn **only where context or bias isolation requires
them** — never by task category, technology, or pipeline layer.

The agent set:

1. **Implementer** — the main Claude Code session, driven by `/work-ticket`. It
   holds full repo context (`CLAUDE.md`, `docs/`, the ticket) and handles all
   `feat` / `fix` / `chore` / `docs` work. It is the session, not a defined
   subagent. One implementer.
2. **`code-reviewer` subagent** (`.claude/agents/code-reviewer.md`) — a fresh
   context window that has not seen the implementation reasoning. First-pass
   review.
3. **CI reviewer** — the GitHub Actions Claude review (Phase 2). A cold, separate
   process that sees only the diff and PR description. The authoritative
   pre-merge gate.

A planning/architect subagent (epic → tickets) may be added later if that work
grows; it is not part of the initial set. Both reviewers are advisory — the human
merge is the gate (D-008, D-013).

**Rationale.** A separate agent is justified only when it must *not* share the
main session's context — for freshness (`code-reviewer`) or full isolation (CI
reviewer). "Chore vs docs", "Bronze vs Silver vs Gold", and "Airflow vs dbt vs
Snowflake" are labels, not structural boundaries: the same conventions, repo, and
context apply. Per-domain agents would duplicate most of their instructions,
drift out of sync with each other and with `CLAUDE.md`, and add cold-start and
orchestration cost with no behavioural gain — a poor trade on a solo, time-boxed
build.

**Where specialization goes instead.**
- **Domain rules → documentation.** Bronze/Silver/Gold responsibilities live in
  `architecture.md`; deeper conventions get a dedicated doc. The implementer
  reads the section the ticket points to.
- **Repeatable procedures → skills.** A recurring checklist (e.g. "how an Airflow
  task is written in this repo") becomes a `.claude/skills/` skill the
  implementer loads when relevant — added once repetition justifies it, not up
  front.
- **Per-task instruction → the ticket.** Acceptance criteria plus links to the
  relevant `docs/` sections are how a ticket says "this is a Bronze task, here
  are the rules."
- **Output category → the commit type.** `feat` / `fix` / `chore` / `docs` label
  the change; they are not a reason for a different worker.

**Consequences.** Intelligence concentrates in tickets and docs — versioned,
reviewable, shared — rather than in a set of agent prompts that must be kept
mutually consistent. Extends D-007 (Claude Code only, no Codex / `AGENTS.md`) and
D-008 (human-gated two-tier review). Operational detail in
`ai-assisted-workflow.md` §3.
