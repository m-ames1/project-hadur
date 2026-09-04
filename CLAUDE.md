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
6. **`docs/git-discipline.md`** — branch model, commits, PRs, branch protection,
   automated branch cleanup. The single git reference.
7. **`docs/handoff-brief.md`** — the full distilled picture, if you need context
   fast.
8. **`docs/open-questions.md`** — choices to make during the build.

`supporting-files/` is gitignored personal notes — background, not repo content.

---

## What this is

A simulated provider→customer data delivery. v1 = one Airflow DAG (local, Docker)
moving a transactional feed through staging → intermediate → marts (dbt's
native layering; the medallion Bronze/Silver/Gold pattern is a v2 Databricks
term, see D-018), cleaning dirty data, joining to a supporting table, and
publishing a customer-ready **table** into Snowflake (DuckDB for local dev).
v2 (future) migrates the whole platform to Databricks / Lakeflow.

**Two goals:** prove real data-engineering capability, and demonstrate an
AI-enabled Jira → agent → review → human-merge workflow.

---

## Non-negotiables

- **Python 3.12 via pyenv.** Not the newest Python, not macOS system Python.
- **Branch off `main`; never commit to `main`.** `main` has admin-enforced branch
  protection (D-013): PR required, force-push and deletion blocked. Claude Code
  **may open PRs** (`git push` a feature branch, `gh pr create`) but **must never
  merge them** (D-012) — every merge is a human action on github.com. Reviews
  (subagent + CI) are advisory. Full rules: `docs/git-discipline.md`.
- **SemVer from `0.0.0`.** `VERSION` + git tags + `CHANGELOG.md`. Stay in `0.x`
  through v1. Era tags: `airflow-platform-v1`, `databricks-platform-v2`.
- **Raw = source data loaded into warehouse tables (not a dbt model); staging,
  intermediate, and marts = dbt models in the warehouse** (DuckDB local,
  Snowflake demo). Raw inputs stay CSV/JSON/TXT. Customer delivery is a
  Snowflake table (a marts model). No Parquet-between-layers contract.
- **Transformation is dbt SQL, portable across adapters** (DuckDB ↔ Snowflake ↔
  Databricks). Keep any Python transform helpers thin.
- **Supplier-specific logic stays isolated under `src/<supplier>/`** and dbt
  models under `models/<supplier>/` or tagged `supplier:<name>`. Do not split
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

- **Git — branch naming, commits, PRs, merge, cleanup:** see
  `docs/git-discipline.md`. In short: branch `hadur-nn-<slug>` off `main`,
  Conventional Commits, squash-merge, human merges.
- Tests: `pytest` for transform functions with real logic.
- Airflow tasks are `PythonOperator`s calling `src/` functions. One DAG in v1.
- **dbt** — models live in `dbt/models/`, tested with `dbt test`; Airflow runs
  dbt via `BashOperator`. Two profile targets: `duckdb` (default) and
  `snowflake` (demo), configured in `~/.dbt/profiles.yml` (never committed;
  secrets via `env_var()` only).
