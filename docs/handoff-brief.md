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

- **v1 — Airflow-orchestrated platform.** Built end to end first, locally.
- **v2 — Databricks / Lakeflow rebuild.** Done as a *migration off* the working
  v1, not a fresh build.

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

- **One DAG:** the transactional supplier-data pipeline, Bronze → Silver → Gold,
  with a data-quality check gating Gold.
- Cleaning dirty data through the Bronze/Silver/Gold layers.
- **The join:** Gold joins transactions to one supporting/entity table
  (members *or* providers — pick during build).
- **Reference data is NOT a pipeline.** Keep `reference_codes.csv` as a static
  lookup that Silver validates against and enriches from. Invalid codes →
  quarantine. This shows reference-code handling without a second DAG.
- Orchestration by **Airflow, running locally in Docker.**
- **Claude Code only.** No Codex, no `AGENTS.md` for v1 (10-minute add later;
  recorded as a deliberate scope cut).

Out of scope for v1: reference-data pipeline, analytics pipeline as a separate
DAG, any cloud infra, Databricks.

---

## 4. Architecture (v1)

Lakehouse-style Bronze / Silver / Gold, orchestrated as one Airflow DAG.

**DAG shape:**

```
bronze_ingest
  → silver_clean
  → silver_validate
  → silver_dedupe
  → dq_check            (fails the DAG if DQ thresholds are breached)
  → gold_build          (produces Gold Parquet)
  → gold_publish        (loads the delivered table into Postgres)
  → delivery_manifest   (writes delivery_log row + human-facing artifacts)
```

Tasks are `PythonOperator`s calling functions in `src/`. Supplier-specific logic
stays isolated under `src/` so a future "extract a supplier into its own repo"
step is plausible (the Theseus pattern) — do not split now.

**Layer responsibilities:**

- **Bronze** — ingest raw source files, land as Parquet, capture metadata, log
  row counts, no destructive transforms.
- **Silver** — clean (casing, date parsing, trimming, type coercion), validate
  schema, validate reference codes, deduplicate (transactional dedup +
  late-arriving records: latest `updated_at` wins), quarantine bad rows to a
  quarantine table + reject log, emit DQ metrics.
- **Gold** — join to the supporting table, apply customer delivery rules (column
  selection, renames, formats, derived fields), build the delivered table,
  produce the delivery manifest and a human-readable DQ summary.

**Compute engine:** write transform functions engine-agnostic at the boundary
(in path → out path, operate on a DataFrame). Use **PySpark local mode**; fall
back to **pandas/polars** the moment Spark-in-Docker eats more than half a day.
The Parquet contract makes the engine swappable — that swappability is itself a
point in the v2 story.

---

## 5. File formats

Short version: **CSV/JSON/TXT in → Parquet (v1) / Delta (v2) through the middle →
a delivered table out.** Parquet between layers is the deliberate pivot that makes
the v2 upgrade a swap, not a rewrite.

| Stage | v1 — Airflow, local | v2 — Databricks |
|---|---|---|
| Provider inputs (raw landing) | `transactions.csv`, supporting `.csv`, `reference_codes.csv`, `payload_metadata.json`, `provider_notes.txt` | **Same files, unchanged** — land in a cloud volume, ingested by Auto Loader |
| Bronze storage | **Parquet**, partitioned by ingest date / run id | **Delta table** in Unity Catalog |
| Silver storage | **Parquet**, partitioned | **Delta table** |
| Gold storage | **Parquet** | **Delta table** |
| Quarantine / rejects | Parquet table + human-readable reject log (CSV/JSON) | Delta table + expectations metrics |
| Run metadata / DQ metrics | **JSON** sidecar files | Pipeline **event log** + Unity Catalog **system tables** |
| DQ summary (business-readable) | **Markdown** | **Markdown** |
| Customer delivery (egress) | **Postgres table** (primary) + Parquet copy + CSV extract + JSON manifest | Gold **Delta table** in `prod_catalog.gold`, consumed via SQL warehouse or **Delta Sharing** |

Never use CSV between layers — it loses types and schema and can't be the on-ramp
to Delta.

`provider_notes.txt` stays a text input in both eras. A task parses/classifies it
(keyword rules or a Claude call) and emits structured rows — Parquet in v1, Delta
in v2.

---

## 6. Delivery: an actual table, not CSV files

Earlier framing of "the customer always gets CSV" was corrected. CSV-over-SFTP is
one common external pattern; warehouse-to-warehouse **table** delivery (a loaded
table, a data share) is at least as common now and is more production-shaped.

**v1 mechanism:** reuse the **Postgres already running** in the Airflow
docker-compose. Add a dedicated database or schema as the "delivery warehouse."
`gold_publish` loads `delivery.<customer>_<dataset>`. Keep a Parquet copy and a
CSV extract as secondary audit artifacts.

**Between Gold Parquet and the delivered table (`gold_publish`):**
- Explicit DDL — column types, nullability, primary key on the business key.
- Column selection / renaming to the customer contract.
- Apply delivery rules (filters, derived fields, formatting).
- Load strategy — full replace, or upsert / `MERGE` on business key for reruns.
- Add delivery metadata columns: `delivery_run_id`, `delivered_at`.
- Table comment + a row in a `data_dictionary` table.

**`delivery_manifest`:** writes a row into a `delivery_log` table (row count,
checksum, run id, timestamp) and drops the human-facing artifacts (CSV extract,
Markdown DQ summary).

**v2 mapping:** `gold_publish` is the one task that changes — Postgres load
becomes a managed Delta table in `prod_catalog.gold`; consumption becomes a SQL
warehouse query or Delta Sharing. Near-zero-diff on the Gold columns and business
key.

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
backward-compatible new capability (e.g. adding the Silver layer); MAJOR only at
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
- PySpark local mode (or pandas/polars fallback).
- Airflow via trimmed official docker-compose: webserver, scheduler, Postgres,
  **LocalExecutor** (not Celery/k8s). Drop Flower; `AIRFLOW__CORE__LOAD_EXAMPLES=false`.
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
