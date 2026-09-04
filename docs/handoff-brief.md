# Handoff Brief — project-hadur

**Purpose of this file:** the distilled, high-fidelity capture of the planning
conversation that scoped this project. It is the source the other `docs/` files
are split from. Read it once to load the whole picture; then work from
`project-status.md` + `project-plan.md` + the relevant reference doc.

Captured 2026-09-03.

---

## 1. Project identity

**Name:** AI-Enabled Data Pipeline Modernization Capstone (repo: `project-hadur`).

A simulated enterprise data-delivery relationship: one provider sends multiple
messy source files (structured, semi-structured, unstructured); one customer
expects cleaned, validated, delivery-ready output. All synthetic data,
deliberately seeded with realistic quality problems.

**Two goals at once:**
1. Prove real, independent data-engineering capability (personal — not just a
   portfolio artifact).
2. Demonstrate a modern AI-enabled engineering workflow (Jira → coding agent →
   review → human merge).

**Interview framing:** "I designed and built a data-engineering workflow the way
an AI-enabled team builds it now — clear specs, architecture notes, coding-agent
guidance, review discipline, documentation, and a platform-modernization story."

---

## 2. The two-era platform (the headline structural decision)

Committed 2026-09-01. The project is deliberately staged as a **platform
modernization**, not a local build lifted to the cloud:

- **v1 — Airflow-orchestrated platform**, transformation in **dbt**, warehouse
  is **DuckDB (local dev/CI) / Snowflake (demo)** (D-017). Built end to end
  first, locally.
- **v2 — Databricks migration design.** Done as a *migration off* the working
  v1, not a fresh build (D-017 unaffected).

The migration is itself a deliverable: one architecture diagram per platform, a
migration decision record, the Airflow→Databricks component-mapping table filled
in with actuals, before/after operational metrics (task count, latency, code
volume), DAG-view vs pipeline-graph screenshots, a recorded failure-and-recovery
demo, and era git tags `airflow-platform-v1` / `databricks-platform-v2`.

**Known risk:** two production-grade platforms can balloon into months. Mitigation
— keep Airflow deliberately minimal. The payoff is the migration analysis, not
Airflow production-ops mastery.

**This brief and the 5-day plan below cover v1 only.** v2 is future work.

---

## 3. The 5-day v1 scope

Five days, hard limit. In scope:

- **One DAG:** the transactional supplier-data pipeline, raw → staging →
  intermediate → marts (dbt-native naming, D-018), with a data-quality check
  gating the marts layer.
- Cleaning dirty data through the staging/intermediate layers.
- **The join:** the mart joins transactions to one supporting/entity table
  (members *or* providers — pick during build).
- **Reference data is NOT a pipeline.** Keep `reference_codes.csv` as a static
  lookup that the intermediate layer validates against and enriches from.
  Invalid codes → quarantine. This shows reference-code handling without a
  second DAG.
- Orchestration by **Airflow, running locally in Docker.**
- **Claude Code only.** No Codex, no `AGENTS.md` for v1 (10-minute add later;
  recorded as a deliberate scope cut).

Out of scope for v1: reference-data pipeline, analytics pipeline as a separate
DAG, any cloud infra, Databricks.

---

## 4. Architecture (v1)

Raw / staging / intermediate / marts — dbt's native layering (D-018), not the
Databricks-coined medallion Bronze/Silver/Gold naming — orchestrated as one
Airflow DAG, with staging/intermediate/marts implemented as **dbt models**.

**DAG shape:**

```
land_raw
  → load_raw               (raw files -> warehouse raw tables;
                            reference_codes.csv via dbt seed)
  → dbt_run_staging        (dbt run  --select staging intermediate)
  → dbt_test_intermediate  (dbt test --select staging intermediate —
                            DQ GATE: fails DAG on breach)
  → dbt_run_marts          (dbt run  --select marts)
  → dbt_test_marts         (dbt test --select marts)
  → publish_marts          (verify row count vs dq_metrics; write delivery_log row;
                            drop CSV extract + Markdown DQ summary)
  → notify (optional)
```

`land_raw`/`load_raw` are `PythonOperator`/`BashOperator` tasks calling
functions in `src/`; `dbt_run_*`/`dbt_test_*` invoke dbt via `BashOperator`.
Supplier-specific logic stays isolated under `src/` and, where relevant,
`dbt/models/<supplier>/` so a future "extract a supplier into its own repo"
step is plausible (the Theseus pattern) — do not split now.

**Layer responsibilities:**

- **Raw** (`load_raw`, not dbt) — load raw source files into warehouse
  `raw` tables; `reference_codes.csv` via `dbt seed`; capture ingest
  metadata, log row counts; no destructive transforms. dbt only reaches this
  layer via `source()`.
- **Staging** (dbt models) — `stg_transactions`/`stg_<entity>` clean (casing,
  date parsing, trimming, type coercion). Thin, 1:1 with the raw source.
- **Intermediate** (dbt models) — `int_transactions_validated`
  checks schema + reference codes as dbt tests; `int_transactions_deduped`
  dedupes (transactional dedup + late-arriving records: latest `updated_at`
  wins via `qualify row_number()`); `int_quarantine_transactions` (+
  `reject_log`) reproduces the bad-row predicate via a shared macro so
  quarantine and exclusion stay in sync; `int_dq_metrics` emits counts.
- **Marts** (dbt models) — `<customer>_<dataset>` joins to the supporting
  table, applies customer delivery rules (column selection, renames, formats,
  derived fields), materializes the delivered table; `delivery_log` and
  `data_dictionary` models; `publish_marts` (Airflow task) verifies row count,
  writes the `delivery_log` row, and drops the CSV extract + Markdown DQ
  summary.

**Transformation engine:** dbt SQL, portable across adapters — the same models
run on **DuckDB** (local dev/CI) and **Snowflake** (deployed demo), and later
Databricks/Spark SQL in v2. That adapter portability is itself a point in the
v2 story (D-017).

---

## 5. File formats

Short version: **CSV/JSON/TXT in → dbt models building warehouse tables through
the middle → a delivered table out**, on DuckDB locally and Snowflake for the
demo (v1), Delta tables in v2. dbt's portability across adapters is the
deliberate pivot that makes the v2 upgrade a storage/engine swap, not a
transformation rewrite.

v1 uses dbt-native staging/intermediate/marts naming; v2's Bronze/Silver/Gold
is the idiomatic Databricks term for the same conceptual tiers (D-018).

| Stage | v1 — Airflow + dbt, DuckDB/Snowflake | v2 — Databricks |
|---|---|---|
| Provider inputs (raw landing) | `transactions.csv`, supporting `.csv`, `reference_codes.csv`, `payload_metadata.json`, `provider_notes.txt` | **Same files, unchanged** — land in a cloud volume, ingested by Auto Loader |
| Raw storage | warehouse `raw` tables (DuckDB local / Snowflake demo), loaded by `load_raw` | **Delta table** in Unity Catalog (Bronze) |
| Staging + intermediate storage | dbt models materialized in the warehouse | **Delta table** (Silver) |
| Marts storage | dbt models materialized in the warehouse | **Delta table** (Gold) |
| Quarantine / rejects | `int_quarantine_transactions` dbt model + `reject_log` export | Delta table + expectations metrics |
| Run metadata / DQ metrics | `int_dq_metrics` dbt model / `raw._ingest_log` | Pipeline **event log** + Unity Catalog **system tables** |
| DQ summary (business-readable) | **Markdown** | **Markdown** |
| Customer delivery (egress) | **Snowflake table** (primary; DuckDB locally) + CSV extract + Markdown DQ summary | Gold **Delta table** in `prod_catalog.gold`, consumed via SQL warehouse or **Delta Sharing** |

`provider_notes.txt` stays a text input in both eras. A task parses/classifies it
(keyword rules or a Claude call) and emits structured rows loaded to a
staging/intermediate table.

---

## 6. Delivery: an actual table, not CSV files

Earlier framing of "the customer always gets CSV" was corrected. CSV-over-SFTP is
one common external pattern; warehouse-to-warehouse **table** delivery (a loaded
table, a data share) is at least as common now and is more production-shaped.

**v1 mechanism:** the customer dataset is a table built by the
`<customer>_<dataset>` **dbt model** in a Snowflake `marts`
schema (DuckDB locally). Column selection/renaming, delivery rules (filters,
derived fields, formatting), and `unique`+`not_null` tests on the business key
live in the dbt model itself — not a separate load step.

**`publish_marts` (Airflow task, runs after the dbt marts models):**
- Verify the mart's row count matches `dq_metrics`.
- Write a row into the `delivery_log` dbt model (row count, checksum,
  `dag_run_id`, `delivered_at`, status).
- Drop the human-facing artifacts: a CSV extract and a Markdown DQ summary, as
  secondary audit artifacts alongside the Snowflake table.
- `data_dictionary` model documents columns from `schema.yml`.

**v2 mapping:** the marts dbt models keep running (dbt-databricks); the target
warehouse changes — Snowflake table becomes a managed Delta table in
`prod_catalog.gold`; consumption becomes a SQL warehouse query or Delta
Sharing. Near-zero-diff on the mart's columns and business key.

---

## 7. The AI-assisted engineering workflow

The loop this project is meant to demonstrate: **Jira card → Claude Code builds it
on a branch → separate review → GitHub notifies → human reviews and merges.**

**Components:**

| Requirement | Mechanism |
|---|---|
| Start from Jira cards | Atlassian MCP server connected to Claude Code |
| Claude does the work | `/work-ticket` slash command encoding the full ticket→PR loop |
| Separate review agent | `code-reviewer` subagent (fast, local, fresh context) **+** Claude review in CI (cold, authoritative — sees only the diff) |
| Notified when ready | GitHub "review requested" on the PR, shown in the github.com notifications inbox (bell). No email, no phone. |
| You review + merge | Branch-protected `main`, PR required, merge transitions the Jira card |

**Key design point on "no bias":** a subagent in the same session still inherits
repo conventions and `CLAUDE.md`. The genuinely cold reviewer is the CI one — a
separate process that only ever sees the diff and PR description, never the
implementation reasoning. Use both: subagent = fast first pass (like a linter with
judgment), CI = the gate.

**Agent topology (D-015):** the implementer (the main session via `/work-ticket`)
and the `code-reviewer` subagent. A GitHub Actions review job is a defined third
layer but **deferred to Phase 2 (D-016)** — v1 runs the subagent plus the human
PR review. Agents are split only for context/bias isolation, never by task type,
technology, or pipeline layer. Domain specialization lives in docs, skills, and
ticket scope — not in per-domain agents. Full treatment in
`ai-assisted-workflow.md` §3.

**These are config files, not an application.** `.claude/agents/code-reviewer.md`
(subagent), `.claude/commands/work-ticket.md` (slash command),
`.claude/settings.json` (hooks), `.mcp.json` (Jira connection). Built by talking
to Claude Code, reviewed like any PR. The only real code is a ~30-line GitHub
Actions workflow for the CI review. This is *not* the Managed Agents / API product
(that cookbook is a different thing — building a hosted agent application in
Python/TS; wrong tool here).

**Phasing:**
- **Phase 0** — foundations: branch protection, Jira project + ticket template,
  Atlassian MCP, `code-reviewer` subagent, `/work-ticket` command, Jira↔GitHub
  linking.
- **Phase 1** — assisted loop, human-triggered: you run `/work-ticket HADUR-nn`.
- **Phase 2** — CI review gate: Claude review on every PR, required status check;
  the notification fires after it passes.
- **Phase 3** — full automation (Jira webhook dispatches the Action headlessly).
  **Deferred** — only after Phases 1–2 run cleanly on real tickets.

**Things to get right (all endorsed):**
- Never let the flow merge itself. Human merge is the gate; both review layers are
  advisory. Branch protection enforces it.
- The truly unbiased review is the CI one (separate process, artifact only).
- Underspecified tickets bounce — no best-guess implementation. Build that check
  into `/work-ticket`.
- The workflow is capstone content — document it.
- Cost: headless runs + CI reviews burn tokens per ticket. Trivial at capstone
  scale; note before Phase 3.

---

## 8. Versioning discipline (Theseus precedent)

Real SemVer from `0.0.0`. Stay in `0.x` while pre-first-full-slice. `VERSION` file
(or `pyproject.toml` version) + real git tags + `CHANGELOG.md`, so the version
history is an actual artifact. PATCH = behavior-preserving fixes; MINOR =
backward-compatible new capability (e.g. adding the intermediate layer); MAJOR only at
1.0+ for a broken pipeline contract. Era tags `airflow-platform-v1` /
`databricks-platform-v2` mark the migration.

---

## 9. Architecture-evolution story (Theseus precedent)

Theseus (prior real work): started as a monolith containing all suppliers → core
pipeline extracted → each supplier split into its own repo. Here: one provider /
one customer, so do **not** split now. Keep supplier logic isolated under `src/`
so an extraction is a natural, demonstrable next step rather than a retrofit. If
synthetic providers get added later, that's the trigger to replay the split.

---

## 10. Environment

- **Python 3.12** via **pyenv**, pinned to this project's virtualenv. Not the
  newest Python (wheel lag on PyArrow/Pandas/NumPy), not macOS system Python.
- dbt-core + dbt-duckdb + dbt-snowflake + dbt_utils. `~/.dbt/profiles.yml`
  (not committed) with `duckdb` (default) and `snowflake` (demo) targets.
- Airflow via trimmed official docker-compose: webserver, scheduler, Postgres
  (metadata DB only), **LocalExecutor** (not Celery/k8s). Drop Flower;
  `AIRFLOW__CORE__LOAD_EXAMPLES=false`.
- **v2 (future) Databricks:** single workspace + Unity Catalog with
  `dev`/`staging`/`prod` catalogs (not three workspaces — avoids stray cloud
  networking cost), Databricks Asset Bundles + GitHub Actions, triggered
  pipelines only, aggressive auto-terminate. Estimated total cost ~$5–15.

---

## 11. What v1 is NOT

Not a toy script, not a tutorial, not an AI experiment, not dependent on
confidential employer data, and **not a project that gets blocked by perfect
tooling before the pipeline exists.** Fastest path to a demonstrable, explainable
result — but real, working implementations, not shortcuts that fake depth.

---

## 12. Working rules (from user feedback, persist across sessions)

- **Commit only when explicitly told to, in the moment.** Not proactively, not as
  a side effect of finishing a task. "You can create commits" means "you may run
  `git commit` when I say so," not "commit when you think it's appropriate."
- **Push only when explicitly told to, in the moment.** The instruction is the
  authorization; no extra confirmation needed unless the action is riskier than a
  normal push.
- **Decide/discuss now, execute later** is the recurring rhythm of this project.
  When the user asks for an opinion or evaluation, give it and stop — don't offer
  or start cleanup/setup/build work unless they signal they're starting.
