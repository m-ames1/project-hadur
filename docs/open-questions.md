# Open Questions — project-hadur

Choices deliberately deferred to the build, plus anything unresolved. Resolve
these by adding a record to `decision-log.md` and striking the item here.

---

## To decide during the build

1. **dbt adapter parity (Day 3–5).** Confirm the Silver/Gold models run
   identically on the `duckdb` and `snowflake` targets; note dialect divergence
   (`qualify`, date functions) and where a macro is needed.

2. **Supporting/entity table (Day 2).** `members.csv` or `providers.csv` as the
   table joined in Gold. Pick whichever makes the join and the seeded
   unmatched-ID issues most legible.

3. **Atlassian MCP flavour (Day 1).** Official hosted remote server (OAuth, no
   secrets in repo) vs community `mcp-atlassian` (Docker + API token). Default to
   the official remote server unless it lacks a needed capability.

4. **DQ thresholds (Day 4).** The exact metrics and cutoffs that make `dq_check`
   fail the DAG (e.g. max % quarantined, zero tolerance for schema drift, max
   null rate on required fields). Set during build; record them.

5. **Snowflake delivery schema + object naming (Day 1–5).**
   `<db>.<gold|delivery>.<customer>_<dataset>`; role/warehouse sizing for the
   demo; whether local DuckDB mirrors the schema names.

6. **Customer identity.** Is the "customer" an internal downstream consumer or an
   external party? Affects how v2 framing lands (SQL warehouse query vs Delta
   Sharing). Not blocking v1.

7. **`provider_notes.txt` classification method.** Simple keyword/rule parsing vs
   a Claude call. Keyword rules are cheaper and fully offline; a Claude call is a
   better "AI-enabled" story. Decide when building the Unstructured epic.

8. **Snowflake trial timing.** Create the trial on/around Day 5 so the 30-day /
   $400 window covers the demo and interview follow-up; until then all work is
   on DuckDB.

9. **dbt materializations.** Table vs incremental for
   `silver_transactions_deduped`, `gold_*`, `delivery_log`; view vs table for
   staging.

---

## Resolved

- **Notification mechanism** → GitHub "review requested" in the github.com
  notifications inbox only. `Stop`-hook phone/desktop push explicitly rejected.
  (D-008)
- **Delivery format** → a real table (Snowflake in v1; DuckDB locally), not CSV
  files. (D-005 superseded by D-017.)
- **Codex / AGENTS.md in v1** → no. (D-007)
