# Architecture — project-hadur v1

Scope: the v1 Airflow-orchestrated platform. The Databricks v2 target is described
only as a migration mapping at the end. See `decision-log.md` for why each choice
was made.

---

## 1. Overview

A synthetic provider sends messy source files. One Airflow DAG loads the
**transactional** feed into a warehouse, then dbt models clean and validate it
through Bronze / Silver / Gold, join it to a supporting table, and publish a
customer-ready table into a Snowflake delivery schema (DuckDB locally).

```
                 raw files (CSV / JSON / TXT)
                          │
        ┌─────────────────▼─────────────────┐
        │  Airflow DAG (local, docker)      │
        │                                   │
        │  land_raw                         │  verify raw files present; archive a copy
        │      │                            │
        │  load_bronze                      │  raw → warehouse raw/bronze tables;
        │      │                            │  reference_codes.csv via dbt seed
        │  dbt_run_silver                   │  dbt run --select bronze silver
        │      │                            │
        │  dbt_test_silver ──► fail DAG if  │  DQ GATE: dbt tests on Silver
        │      │               breached     │
        │  dbt_run_gold                     │  dbt run --select gold
        │      │                            │
        │  dbt_test_gold                    │  dbt test --select gold
        │      │                            │
        │  publish_gold                     │  verify row count vs dq_metrics;
        │      │                            │  write delivery_log row; drop
        │      │                            │  CSV extract + Markdown DQ summary
        │  notify (optional)                │
        └───────────────────────────────────┘
                          │
        Snowflake delivery table (DuckDB locally)  +  CSV extract  +  Markdown DQ summary
```

`land_raw` and `load_bronze` are `PythonOperator`/`BashOperator` tasks calling
`src/` helpers; `dbt_run_*` / `dbt_test_*` invoke dbt via `BashOperator`
(subprocess) — cosmos is an optional later choice, not required. One DAG only.

---

## 2. Source data (synthetic)

Landed into a raw input directory, simulating a provider drop:

| File | Type | Role |
|---|---|---|
| `transactions.csv` | CSV | the transactional feed (the pipeline's subject) |
| `<members\|providers>.csv` | CSV | supporting/entity table, joined in Gold |
| `reference_codes.csv` | CSV | static lookup — Silver validates + enriches against it |
| `payload_metadata.json` | JSON | batch metadata (row counts, source, sent-at) |
| `provider_notes.txt` | TXT | unstructured notes; a task parses/classifies → structured rows |

**Seeded quality issues** (deliberate): missing values, duplicate records, invalid
reference codes, schema drift, malformed dates, inconsistent casing, unmatched
IDs, null-heavy fields, late-arriving records, notes needing classification, rows
that should be quarantined.

---

## 3. Layer responsibilities

Medallion names are kept for the narrative (`models/bronze|silver|gold/`); this
maps to dbt's idiomatic staging/intermediate/marts split.

### Bronze — `load_bronze` (Airflow task, not a dbt model)
- Load `transactions.csv` and the entity table (`members.csv` or
  `providers.csv`) into a warehouse `raw`/`bronze` schema (DuckDB
  `read_csv_auto`/`COPY`; Snowflake stage + `COPY INTO`).
- `reference_codes.csv` is loaded via `dbt seed`.
- Raw files archived to `data/raw/archive/<run_id>/`.
- Capture ingest metadata + row counts to a `bronze._ingest_log` table or JSON
  sidecar.
- No transforms — preserve raw structure and values.

### Silver — dbt models
- `stg_transactions`, `stg_<entity>`: casing, trims, date parsing, casts.
- `silver_transactions_validated`: schema/null/range rules as dbt tests;
  reference-code check via `relationships` / `accepted_values` against the
  `reference_codes` seed.
- `silver_transactions_deduped`: `qualify row_number() over (partition by
  <business_key> order by updated_at desc) = 1` — also resolves late-arriving
  records.
- `quarantine_transactions`: a model, not a stored test-failure table. It
  reproduces the bad-row predicate via a **shared macro** (e.g.
  `is_invalid_transaction_row(...)`), so the same logic both excludes rows
  from `silver_transactions_validated`/`silver_transactions_deduped` and
  includes them here with a computed `reject_reason` column. Do **not** use
  dbt's `store_failures` for this — it produces one table per failing test,
  not the single human-readable table this design wants. `reject_log` is a
  human-readable export of the same model.
- `dq_metrics`: counts (in, cleaned, quarantined, dedup-removed, invalid-code,
  null-violations).

### DQ gate — `dbt_test_silver`
- `dbt test --select silver` as its own Airflow task. Non-zero exit fails the
  DAG — the gate before anything customer-facing is built. Optional singular
  test for thresholds (e.g. `quarantined_pct <= X`); thresholds are still an
  open question, set at build (see `open-questions.md`).

### Gold — dbt models + `publish_gold`
- `gold_<customer>_<dataset>`: join deduped transactions to the entity table,
  apply delivery rules, materialized as a table; `unique` + `not_null` tests
  on the business key.
- `delivery_log`: one row per run — `row_count`, `checksum`, `dag_run_id`,
  `delivered_at`, `status`.
- `data_dictionary`: generated from `schema.yml` column descriptions.
- **`publish_gold`** (Airflow task): verify Gold row count matches
  `dq_metrics`, write the `delivery_log` row, drop
  `data/delivery/<customer>_<dataset>_<run_id>.csv` and the Markdown DQ
  summary.

### Unstructured
- `provider_notes.txt` parsed/classified by a Python task (keyword rules or a
  Claude call — open question) into rows loaded to a bronze/silver table,
  surfaced in Gold only if in the customer contract.

---

## 4. File formats

| Stage | Format | Notes |
|---|---|---|
| Raw inputs | CSV / JSON / TXT | as the provider "sends" them; raw archive kept as-is |
| Bronze / Silver / Gold | warehouse tables (DuckDB local / Snowflake demo) | built by dbt (Silver, Gold) and `load_bronze` (Bronze) |
| Quarantine | `quarantine_transactions` dbt model + `reject_log` export | table for data, log for humans |
| Run metadata / DQ metrics | `dq_metrics` dbt model / `bronze._ingest_log` | in-warehouse, not sidecar files |
| DQ summary | Markdown | business-readable, dropped by `publish_gold` |
| Customer delivery | Snowflake table (primary; DuckDB locally) + CSV extract + Markdown DQ summary | |

Rationale: `decision-log.md` D-017 (supersedes D-004, D-005).

---

## 5. Delivery table (`publish_gold`)

**Target:** a Snowflake `gold`/`delivery` schema in the deployed demo; the
equivalent schema in the local DuckDB file for dev/CI. Table
`gold_<customer>_<dataset>` is the dbt model that builds it — see §3.

**`publish_gold` Airflow task (post-dbt):**
- Verify the Gold row count matches `dq_metrics`.
- Write the `delivery_log` row (see below).
- Drop `data/delivery/<customer>_<dataset>_<run_id>.csv` and the Markdown DQ
  summary as secondary audit artifacts.

**Built by the dbt models themselves (not `publish_gold`):**
- Column selection / renaming to the customer contract, delivery rules
  (filters, derived fields, formatting) — in the `gold_<customer>_<dataset>`
  model.
- `unique` + `not_null` tests on the business key.
- `data_dictionary` model, generated from `schema.yml` column descriptions.

**`delivery_log` model columns:** `dag_run_id`, `dataset`, `row_count`,
`checksum`, `delivered_at`, `status`.

---

## 6. Local infrastructure

- **Airflow** via trimmed official `docker-compose.yaml`:
  - services: `airflow-webserver`, `airflow-scheduler`, `postgres`
  - `AIRFLOW__CORE__EXECUTOR=LocalExecutor`
  - Flower removed; `AIRFLOW__CORE__LOAD_EXAMPLES=false`
  - DAGs bind-mounted from `pipelines/` (or `dags/`); `src/` importable
  - The `postgres` service is **Airflow's metadata database only** — it is not
    a data-delivery target.
- **dbt project** (`dbt/`): dbt-core + dbt-duckdb + dbt-snowflake + dbt_utils.
  Two targets in one `profiles.yml`: `duckdb` (default, local dev + CI,
  `data/warehouse/hadur.duckdb`) and `snowflake` (demo, via env vars).
  `profiles.yml` lives at **`~/.dbt/profiles.yml`, not committed** — standard
  dbt practice — with real values supplied via `env_var()` only. The repo
  includes `dbt/profiles.yml.example` (placeholders only) for onboarding.
- **Python 3.12** via pyenv for local dev / tests outside the containers, and
  for running dbt/Airflow.

---

## 7. Repo structure (target)

```
project-hadur/
  README.md
  CLAUDE.md
  VERSION
  CHANGELOG.md
  pyproject.toml
  .mcp.json                     # Jira (Atlassian MCP)
  .claude/
    agents/code-reviewer.md
    commands/work-ticket.md
    settings.json               # hooks (committed); settings.local.json stays ignored
  .github/workflows/
    code-review.yml             # cold Claude review on PRs (Phase 2)
  docker/
    docker-compose.yaml
    Dockerfile                  # Airflow image
  pipelines/ (or dags/)
    transactional_pipeline.py   # the one DAG
  dbt/
    dbt_project.yml
    packages.yml                 # dbt_utils
    profiles.yml.example         # template only, placeholders via env_var();
                                  # real profiles.yml lives at ~/.dbt/profiles.yml,
                                  # never committed (standard dbt practice)
    models/
      bronze/  silver/  gold/
      _sources.yml  _schema.yml
    seeds/reference_codes.csv
    macros/                      # incl. the shared bad-row predicate used by
                                  # silver_transactions_validated + quarantine_transactions
    tests/                       # singular tests (thresholds, invariants)
  src/
    ingestion/                   # raw -> warehouse loaders
    notes/                       # unstructured parsing
    validation/                  # non-dbt checks only
    utils/
    <supplier>/                  # supplier-specific logic, isolated (Theseus)
  data/
    raw/
      archive/
    warehouse/hadur.duckdb
    delivery/
  tests/
  synthetic/                    # data generator
  docs/
  demo/
```

`src/` drops `transformations/` (now dbt); `validation/` shrinks to non-dbt
checks only. `data/` drops the Parquet-era `bronze/ silver/ gold/ quarantine/`
directories.

`.gitignore` adds: dbt build artifacts (`dbt/target/`, `dbt/dbt_packages/`,
`dbt/logs/`) and the local DuckDB file (`data/warehouse/*.duckdb`).

Supplier-specific logic stays under `src/<supplier>/` and, where relevant,
`models/<supplier>/` (or a `supplier:` tag) so a future extraction into its own
repo is a natural step, not a retrofit (D-011).

---

## 8. Databricks v2 migration mapping (future)

| v1 (Airflow + dbt + DuckDB/Snowflake) | v2 (Databricks) |
|---|---|
| Airflow DAG | Lakeflow Job / Databricks Workflow |
| `load_bronze` Python task | Auto Loader ingestion |
| dbt models (bronze/silver/gold) | dbt-on-Databricks OR Lakeflow declarative pipeline |
| dbt tests | dbt tests on Databricks / Lakeflow expectations (`@dlt.expect`) |
| DuckDB (local) / Snowflake (demo) | Delta tables in Unity Catalog (`dev`/`staging`/`prod`) |
| Snowflake `gold`/`delivery` table | Managed Delta table in `prod_catalog.gold` |
| Customer reads Snowflake | SQL warehouse query / Delta Sharing |
| docker-compose + dbt profile target | Databricks Asset Bundles + dbt profile target |
| local `data/` volume | cloud storage volume |
| pyenv virtualenv | cluster runtime |

Because dbt is portable (dbt-databricks), v2 swaps the storage layer and
optionally the declarative-pipeline engine rather than rewriting transformation
logic — a smaller, lower-risk migration than a Python/Spark rebuild.

What the migration writeup must show explicitly: one architecture diagram per
platform, a migration decision record, this table filled with actuals,
before/after metrics (task count, latency, code volume), DAG-view vs
pipeline-graph screenshots, a recorded failure-and-recovery demo, era tags
`airflow-platform-v1` / `databricks-platform-v2`.
