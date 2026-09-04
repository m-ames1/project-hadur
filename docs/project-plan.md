# Project Plan — project-hadur v1 (5 days)

The v1 build plan. Scope is fixed by `decision-log.md` D-002. Each day has one
deliverable and an exit criterion — if the exit criterion isn't met, the day
isn't done.

The living state of execution is in `project-status.md`, not here. This file is
the plan; that file is where you are in it.

---

## Working model across sessions

- The unit of work is a Jira ticket. Layers are sequential (raw → staging →
  intermediate → marts, per D-018), so this is **serial handoff across
  sessions**, not parallel sessions.
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
- Scaffold `dbt/`, install dbt-core + dbt-duckdb + dbt-snowflake + dbt_utils,
  `dbt debug` green on the `duckdb` target, `reference_codes` seed loads.
  `~/.dbt/profiles.yml` set up locally (not committed). Snowflake target
  configured but not required to connect until Day 5.
- Tag `v0.0.0`.

**Exit criterion:** a real ticket can be driven from Jira to a merged PR, with the
`code-reviewer` subagent running, using only Claude Code in the repo.

---

## Day 2 — Synthetic data + raw

- Data generator (`synthetic/`): `transactions.csv`, one supporting table
  (`members.csv` or `providers.csv` — pick here), `reference_codes.csv`,
  `payload_metadata.json`, `provider_notes.txt`. Seed the deliberate quality
  issues (see `architecture.md` §2).
- `load_raw`: loads raw files into DuckDB `raw` schema; `dbt seed`
  for reference codes. Capture ingest metadata; log row counts; no transforms.
- Airflow DAG skeleton with `land_raw` + `load_raw` wired and runnable in
  the local container.
- Confirm dbt runs clean on DuckDB — `dbt run` / `dbt seed` execute without
  adapter errors against the Day 1 scaffold.
- Keep raw archive + ingest log.

**Exit criterion:** `airflow dags trigger transactional_pipeline` runs
`land_raw` and `load_raw` green, and the raw files land in DuckDB `raw`
tables with an ingest log.

---

## Day 3 — Staging + intermediate

- Build the staging dbt models: `stg_transactions`/`stg_<entity>` — thin,
  1:1 cleanup. Then the intermediate models:
  `int_transactions_validated` → `int_transactions_deduped` →
  `int_quarantine_transactions`/`reject_log` → `int_dq_metrics`, with
  `schema.yml` tests (schema, null/range, reference-code
  `relationships`/`accepted_values`).
- `int_quarantine_transactions` reproduces the bad-row predicate via a shared
  macro also used to exclude rows from
  `int_transactions_validated`/`_deduped`, tagging each with a
  `reject_reason` (not dbt's `store_failures`).
- Wire `dbt_run_staging` + `dbt_test_intermediate` into the DAG.

**Exit criterion:** DAG runs `land_raw` → `load_raw` → `dbt_run_staging` →
`dbt_test_intermediate` green; `int_quarantine_transactions` and
`int_dq_metrics` are populated; a known-bad seeded row is provably
quarantined with a reason.

---

## Day 4 — Marts + the join + failure demo

- `dbt_test_intermediate` is the DQ gate — fails the DAG on breached
  thresholds (set the thresholds here; record them).
- Marts dbt models: join deduped transactions to the supporting table;
  apply customer delivery rules; materialize as a table; `unique`+`not_null`
  tests on the business key.
- `publish_marts`: writes the `delivery_log` row + CSV extract + Markdown DQ
  summary; verifies the mart's row count against `int_dq_metrics`.
- **Failure-and-recovery demo:** feed a malformed file → a task fails → fix →
  rerun → success. Record it.

**Exit criterion:** the full DAG runs green end to end; the delivered table
(Snowflake, or DuckDB locally) is queryable with SQL and matches the expected
row count in `delivery_log`; the failure demo is recorded.

---

## Day 5 — Proof + story

- `dbt test` covers model logic; `pytest` covers the remaining Python (loaders,
  notes parser).
- v1 architecture diagram (rendered). Graduate decisions into `docs/` if any are
  still only in notes.
- Do the real run on Snowflake: connect the `snowflake` target, `dbt build
  --target snowflake`, capture screenshots (Snowflake table, `dbt docs` DAG,
  Airflow graph, quarantine, `delivery_log`, delivery manifest).
- README: setup + run instructions (`docker compose up`, trigger the DAG, where
  outputs land, how to query the delivery table on both targets).
- Diagram + README updated for both targets.
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
| **Local platform** | docker-compose · Airflow image · DuckDB warehouse · Snowflake target |
| **dbt project** | `dbt_project.yml` · `~/.dbt/profiles.yml` (duckdb + snowflake, not committed) · seeds · dbt_utils |
| **Synthetic data** | generator · seeded quality issues · data dictionary |
| **Raw** | `load_raw` · ingestion metadata + row-count logging |
| **Staging + intermediate** | dbt models (stg, validated, deduped, quarantine via shared macro, dq_metrics) + schema tests |
| **DQ gate** | `dbt_test_intermediate` task + thresholds |
| **Marts delivery** | marts dbt model (join + rules) · `publish_marts` (Snowflake) · `delivery_log` + `data_dictionary` models |
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
- Snowflake as the primary dev warehouse — DuckDB is dev/CI, Snowflake is the
  Day 5 demo target.
