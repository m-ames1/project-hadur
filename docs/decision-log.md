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
