# Project Plan — project-hadur v1 (5 days)

The v1 build plan. Scope is fixed by `decision-log.md` D-002. Each day has one
deliverable and an exit criterion — if the exit criterion isn't met, the day
isn't done.

The living state of execution is in `project-status.md`, not here. This file is
the plan; that file is where you are in it.

---

## Working model across sessions

- The unit of work is a Jira ticket. Layers are sequential (Bronze → Silver →
  Gold), so this is **serial handoff across sessions**, not parallel sessions.
- Each session: read `project-status.md` → pick up the next ticket → run
  `/work-ticket` → PR → review → merge → update `project-status.md` → end.
- Context-window saving comes from each session being short and single-purpose.
- Detailed tickets are written the morning they're picked up. Only Day 1–2
  tickets are fully specified up front; the rest start as epic + stub.

---

## Day 1 — Operating system + repo foundation

Stand up the delivery mechanism before any pipeline code.

- Repo scaffold per `architecture.md` §7. `pyenv` + Python 3.12 virtualenv.
  `pyproject.toml`, `VERSION` (`0.0.0`), `CHANGELOG.md`, real README.
- `CLAUDE.md` finalized as the session router.
- Branch protection on `main` (PR required).
- Atlassian MCP connected → `.mcp.json` committed.
- `.claude/agents/code-reviewer.md` + `.claude/commands/work-ticket.md`.
- Jira project + epics + ~8–12 tickets with acceptance criteria (Day 2 tickets
  fully specified; rest stubbed).
- Jira ↔ GitHub smart-commit linking.
- **Dry run:** take one throwaway ticket through `/work-ticket` end to end; fix
  the command / subagent prompts from what breaks.
- Start the docker-compose bring-up (can run in the background).
- Tag `v0.0.0`.

**Exit criterion:** a real ticket can be driven from Jira to a merged PR, with the
`code-reviewer` subagent running, using only Claude Code in the repo.

---

## Day 2 — Synthetic data + Bronze

- Data generator (`synthetic/`): `transactions.csv`, one supporting table
  (`members.csv` or `providers.csv` — pick here), `reference_codes.csv`,
  `payload_metadata.json`, `provider_notes.txt`. Seed the deliberate quality
  issues (see `architecture.md` §2).
- `bronze_ingest`: raw → Parquet, partitioned by ingest date / run id; capture
  metadata; log row counts; no transforms.
- Airflow DAG skeleton with `bronze_ingest` wired and runnable in the local
  container.
- **Engine decision:** get PySpark local mode working in the Airflow image, OR
  fall back to pandas/polars — do not burn more than half a day on Spark-in-Docker
  (D-006). Record the outcome in `decision-log.md`.

**Exit criterion:** `airflow dags trigger transactional_pipeline` runs
`bronze_ingest` green and Bronze Parquet lands with a metadata sidecar.

---

## Day 3 — Silver

- `silver_clean`: casing, date parsing, trimming, type coercion.
- `silver_validate`: schema check; reference-code check against
  `reference_codes.csv`; null/range rules.
- `silver_dedupe`: transactional dedup on the business key; late-arriving records
  resolved latest-`updated_at`-wins.
- Quarantine: bad rows → quarantine Parquet table + human-readable reject log.
- DQ metrics JSON.
- All Silver tasks wired into the DAG.

**Exit criterion:** DAG runs Bronze → Silver green; quarantine table and DQ
metrics JSON are produced; a known-bad seeded row is provably quarantined with a
reason.

---

## Day 4 — Gold + the join + failure demo

- `dq_check`: reads Silver DQ metrics; fails the DAG on breached thresholds
  (set the thresholds here; record them).
- `gold_build`: join cleaned transactions to the supporting table; apply customer
  delivery rules; write Gold Parquet.
- `gold_publish`: load `delivery.<customer>_<dataset>` into Postgres — explicit
  DDL, PK on business key, upsert/`MERGE` for idempotent reruns, delivery metadata
  columns, table comment + `data_dictionary` rows.
- `delivery_manifest`: `delivery_log` row + CSV extract + Markdown DQ summary.
- **Failure-and-recovery demo:** feed a malformed file → a task fails → fix →
  rerun → success. Record it.

**Exit criterion:** the full DAG runs green end to end; the delivered Postgres
table is queryable with SQL and matches the expected row count in `delivery_log`;
the failure demo is recorded.

---

## Day 5 — Proof + story

- `pytest` for the transform functions that carry real logic (clean, validate,
  dedupe, join, delivery rules).
- v1 architecture diagram (rendered). Graduate decisions into `docs/` if any are
  still only in notes.
- README: setup + run instructions (`docker compose up`, trigger the DAG, where
  outputs land, how to query the delivery table).
- Screenshots: Airflow DAG graph, a task log, quarantine table, the delivered
  table, `delivery_log`, the delivery manifest.
- Interview demo script / walkthrough notes in `demo/`.
- Tag `v0.1.0`; update `CHANGELOG.md`.
- Run the full Jira → PR → review → merge loop on at least two real tickets so the
  workflow itself is demonstrated, not just described.

**Exit criterion:** someone else could clone the repo, follow the README, run the
pipeline, and query the delivered table — and you can walk the whole thing in a
demo from the docs alone.

---

## Epics / ticket outline

Rough Jira structure — refine acceptance criteria per ticket at pickup time.

| Epic | Tickets (indicative) |
|---|---|
| **Project setup** | repo scaffold · pyenv/3.12 env · VERSION+CHANGELOG+SemVer · branch protection · CLAUDE.md |
| **Agentic workflow** | Atlassian MCP + `.mcp.json` · `code-reviewer` subagent · `/work-ticket` command · Jira↔GitHub linking · CI review workflow (Phase 2) |
| **Local platform** | docker-compose (trimmed) · Airflow image + engine (pyspark/pandas) · delivery Postgres schema |
| **Synthetic data** | generator · seeded quality issues · data dictionary |
| **Bronze** | `bronze_ingest` · ingestion metadata + row-count logging |
| **Silver** | clean · validate (schema + reference codes) · dedupe + late-arriving · quarantine + reject log · DQ metrics |
| **DQ gate** | `dq_check` task + thresholds |
| **Gold delivery** | `gold_build` (join + rules) · `gold_publish` (Postgres table, DDL, upsert) · `delivery_manifest` + `delivery_log` |
| **Unstructured** | parse/classify `provider_notes.txt` → structured rows |
| **Testing & QA** | pytest for transforms · failure-and-recovery demo |
| **Docs & demo** | architecture diagram · README run instructions · screenshots · interview demo script |

---

## Deliberately deferred (not v1)

- Reference-data pipeline; analytics pipeline as its own DAG.
- Phase 3 workflow automation (Jira webhook → headless Action).
- `Stop`-hook notifications.
- Codex / `AGENTS.md`.
- Anything Databricks / cloud (that is v2).
