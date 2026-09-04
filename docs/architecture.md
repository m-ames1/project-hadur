# Architecture — project-hadur v1

Scope: the v1 Airflow-orchestrated platform. The Databricks v2 target is described
only as a migration mapping at the end. See `decision-log.md` for why each choice
was made.

---

## 1. Overview

A synthetic provider sends messy source files. One Airflow DAG moves the
**transactional** feed through a lakehouse Bronze / Silver / Gold flow, cleans and
validates it, joins it to a supporting table, and publishes a customer-ready table
into a Postgres "delivery warehouse."

```
                 raw files (CSV / JSON / TXT)
                          │
        ┌─────────────────▼─────────────────┐
        │  Airflow DAG (local, docker)      │
        │                                   │
        │  bronze_ingest                    │  raw → Parquet, metadata, row counts
        │      │                            │
        │  silver_clean                     │  casing, dates, trims, types
        │      │                            │
        │  silver_validate                  │  schema + reference-code checks
        │      │                            │
        │  silver_dedupe                    │  dedup + late-arriving (updated_at wins)
        │      │                            │
        │  dq_check ────► fail DAG if       │  DQ thresholds
        │      │          breached          │
        │  gold_build                       │  join + delivery rules → Gold Parquet
        │      │                            │
        │  gold_publish                     │  load delivery.<customer>_<dataset> (Postgres)
        │      │                            │
        │  delivery_manifest                │  delivery_log row + CSV extract + MD summary
        └───────────────────────────────────┘
                          │
              Postgres delivery table  +  Parquet copy  +  CSV extract  +  JSON manifest
```

Tasks are `PythonOperator`s calling functions in `src/`. One DAG only.

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

### Bronze — `bronze_ingest`
- Read each raw source file.
- Land as Parquet, partitioned by `ingest_date` (or `run_id`).
- Capture ingestion metadata (source file, row count in/out, ingest timestamp,
  run id) to a JSON sidecar.
- No destructive transforms — preserve raw structure and values.

### Silver — `silver_clean`, `silver_validate`, `silver_dedupe`
- **Clean:** standardize casing, parse/normalize dates, trim whitespace, coerce
  types to the declared schema.
- **Validate:** schema check (columns, types, nullability); reference-code check
  against `reference_codes.csv`; null/range rules. Failing rows are flagged.
- **Dedupe:** transactional dedup on the business key; late-arriving records
  resolved by latest `updated_at` wins.
- **Quarantine:** rows failing validation go to a quarantine Parquet table plus a
  human-readable reject log (reason per row).
- **DQ metrics:** emit a JSON of counts (in, cleaned, quarantined, dedup-removed,
  invalid-code, null-violations, …).

### `dq_check`
- Reads the Silver DQ metrics. Fails the DAG if thresholds are breached
  (thresholds — see `open-questions.md`, to be set during build). This is the gate
  before anything customer-facing is built.

### Gold — `gold_build`, `gold_publish`, `delivery_manifest`
- **`gold_build`:** join cleaned transactions to the supporting table; apply
  customer delivery rules (column selection, renames, formats, derived fields);
  write Gold Parquet.
- **`gold_publish`:** load the delivered table into Postgres (see §5).
- **`delivery_manifest`:** write a `delivery_log` row; drop the CSV extract and
  the Markdown DQ summary.

---

## 4. File formats

| Stage | Format | Notes |
|---|---|---|
| Raw inputs | CSV / JSON / TXT | as the provider "sends" them |
| Bronze / Silver / Gold tables | **Parquet** | partitioned by ingest date / run id; never CSV |
| Quarantine | Parquet + CSV or JSON reject log | table for data, log for humans |
| Run metadata / DQ metrics | JSON | sidecar files |
| DQ summary | Markdown | business-readable |
| Customer delivery | Postgres table (primary) + Parquet copy + CSV extract + JSON manifest | |

Rationale: `decision-log.md` D-004, D-005.

---

## 5. Delivery table (`gold_publish`)

**Target:** the Postgres instance from the Airflow docker-compose, with a
dedicated database or schema `delivery`. Table `delivery.<customer>_<dataset>`.

**Build steps inside `gold_publish`:**
- Explicit DDL: column types, nullability, primary key on the business key.
- Column selection / renaming to the customer contract.
- Apply delivery rules (filters, derived fields, formatting).
- Load strategy: full replace, or upsert / `MERGE` on the business key (so reruns
  are idempotent).
- Delivery metadata columns: `delivery_run_id`, `delivered_at`.
- `COMMENT` on the table; insert/update a row per column in a `data_dictionary`
  table.

**`delivery_log` table columns (indicative):** `delivery_run_id`, `dataset`,
`row_count`, `checksum`, `dag_run_id`, `delivered_at`, `status`.

---

## 6. Local infrastructure

- **Airflow** via trimmed official `docker-compose.yaml`:
  - services: `airflow-webserver`, `airflow-scheduler`, `postgres`
  - `AIRFLOW__CORE__EXECUTOR=LocalExecutor`
  - Flower removed; `AIRFLOW__CORE__LOAD_EXAMPLES=false`
  - DAGs bind-mounted from `pipelines/` (or `dags/`); `src/` importable
- **Delivery Postgres:** either a second database in the same Postgres service, or
  a separate lightweight `postgres` service — decide during build; a separate
  schema in the same DB is the minimum.
- **Compute:** PySpark local mode inside a custom image extending the Airflow
  image (adds `openjdk` + `pyspark`); pandas / polars fallback (D-006).
- **Python 3.12** via pyenv for local dev / tests outside the containers.

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
    Dockerfile                  # Airflow image + Java + pyspark
  pipelines/ (or dags/)
    transactional_pipeline.py   # the one DAG
  src/
    ingestion/
    transformations/
    validation/
    delivery/
    utils/
    <supplier>/                 # supplier-specific logic, isolated (Theseus)
  data/
    raw/  bronze/  silver/  gold/  quarantine/
  tests/
  synthetic/                    # data generator
  docs/
  demo/
```

Supplier-specific logic stays under `src/<supplier>/` so a future extraction into
its own repo is a natural step, not a retrofit (D-011).

---

## 8. Databricks v2 migration mapping (future)

| v1 (Airflow, local) | v2 (Databricks) |
|---|---|
| Airflow DAG | Lakeflow Job |
| `PythonOperator` ingestion task | Auto Loader / ingestion task |
| Python/SQL transform functions | Declarative (Lakeflow) pipeline |
| Parquet directories (Bronze/Silver/Gold) | Delta tables in Unity Catalog |
| `dq_check` custom task | Pipeline expectations (`@dlt.expect`) |
| JSON metadata sidecars | Event log + Unity Catalog system tables |
| Postgres `delivery` schema | Managed Delta table in `prod_catalog.gold` |
| Customer reads Postgres | SQL warehouse query or Delta Sharing |
| docker-compose + Dockerfile | Databricks Asset Bundles |
| local filesystem `data/` | cloud storage volume |
| pyenv virtualenv | cluster runtime |

What the migration writeup must show explicitly: one architecture diagram per
platform, a migration decision record, this table filled with actuals,
before/after metrics (task count, latency, code volume), DAG-view vs
pipeline-graph screenshots, a recorded failure-and-recovery demo, era tags
`airflow-platform-v1` / `databricks-platform-v2`.
