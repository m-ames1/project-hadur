# CLAUDE.md — project-hadur

AI-Enabled Data Pipeline Modernization Capstone. This file is the entry point for
every Claude Code session in this repo.

---

## Start here (read in this order)

1. **`docs/project-status.md`** — where the build currently is; read first, every
   session.
2. **`docs/project-plan.md`** — the 5-day v1 plan, day exit criteria, ticket
   outline.
3. **`docs/decision-log.md`** — what's decided and why. Don't relitigate.
4. **`docs/architecture.md`** — v1 architecture + the Databricks v2 migration
   mapping.
5. **`docs/ai-assisted-workflow.md`** — how a Jira ticket becomes merged code.
6. **`docs/handoff-brief.md`** — the full distilled picture, if you need context
   fast.
7. **`docs/open-questions.md`** — choices to make during the build.

`supporting-files/` is gitignored personal notes — background, not repo content.

---

## What this is

A simulated provider→customer data delivery. v1 = one Airflow DAG (local, Docker)
moving a transactional feed through Bronze → Silver → Gold, cleaning dirty data,
joining to a supporting table, and publishing a customer-ready **table** into
Postgres. v2 (future) migrates the whole platform to Databricks / Lakeflow.

**Two goals:** prove real data-engineering capability, and demonstrate an
AI-enabled Jira → agent → review → human-merge workflow.

---

## Non-negotiables

- **Python 3.12 via pyenv.** Not the newest Python, not macOS system Python.
- **Branch off `main`; never commit to `main`.** Every change goes through a PR.
  The human merges. Reviews (subagent + CI) are advisory.
- **SemVer from `0.0.0`.** `VERSION` + git tags + `CHANGELOG.md`. Stay in `0.x`
  through v1. Era tags: `airflow-platform-v1`, `databricks-platform-v2`.
- **Parquet between Bronze/Silver/Gold layers.** Never CSV between layers. Raw
  inputs are CSV/JSON/TXT; customer delivery is a Postgres table.
- **Transform functions are engine-agnostic at the boundary** (in path → out path
  → Parquet), so the compute engine can be swapped.
- **Supplier-specific logic stays isolated under `src/<supplier>/`.** Do not split
  into multiple repos yet.
- **Claude Code only for v1.** No Codex, no `AGENTS.md`.
- **Underspecified Jira tickets bounce.** Restate acceptance criteria; stop rather
  than guess.

## Working rules

- **Commit only when the user explicitly says to, in that moment.** Not
  proactively, not as a side effect of finishing a task.
- **Push only when the user explicitly says to, in that moment.**
- This project runs decide-now / execute-later. When asked for an opinion or
  review, give it and stop — don't start or offer build/setup work without an
  explicit go.
- End every work session by updating `docs/project-status.md`.

## Conventions

- Branch: `hadur-nn-<short-slug>`. PR body: what/why · ticket link · test evidence
  · `code-reviewer` findings + resolution · handoff notes.
- Commits carry a smart-commit tag (`HADUR-nn ...`); squash-merge with
  `HADUR-nn #done`.
- Tests: `pytest` for transform functions with real logic.
- Airflow tasks are `PythonOperator`s calling `src/` functions. One DAG in v1.
