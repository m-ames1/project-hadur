# Open Questions — project-hadur

Choices deliberately deferred to the build, plus anything unresolved. Resolve
these by adding a record to `decision-log.md` and striking the item here.

---

## To decide during the build

1. **Compute engine (Day 2).** PySpark local mode in a custom Airflow image
   (adds Java + pyspark) vs pandas / polars fallback. Rule: fall back without
   hesitation if Spark-in-Docker costs more than half a day (D-006). Record the
   outcome.

2. **Supporting/entity table (Day 2).** `members.csv` or `providers.csv` as the
   table joined in Gold. Pick whichever makes the join and the seeded
   unmatched-ID issues most legible.

3. **Atlassian MCP flavour (Day 1).** Official hosted remote server (OAuth, no
   secrets in repo) vs community `mcp-atlassian` (Docker + API token). Default to
   the official remote server unless it lacks a needed capability.

4. **DQ thresholds (Day 4).** The exact metrics and cutoffs that make `dq_check`
   fail the DAG (e.g. max % quarantined, zero tolerance for schema drift, max
   null rate on required fields). Set during build; record them.

5. **Delivery Postgres topology (Day 1–4).** Separate schema in the Airflow
   metadata Postgres (minimum), a separate database in the same service, or a
   second `postgres` service. Lean minimal unless the demo benefits from
   visible separation.

6. **Customer identity.** Is the "customer" an internal downstream consumer or an
   external party? Affects how v2 framing lands (SQL warehouse query vs Delta
   Sharing). Not blocking v1.

7. **`provider_notes.txt` classification method.** Simple keyword/rule parsing vs
   a Claude call. Keyword rules are cheaper and fully offline; a Claude call is a
   better "AI-enabled" story. Decide when building the Unstructured epic.

---

## Resolved

- **Notification mechanism** → GitHub "review requested" in the github.com
  notifications inbox only. `Stop`-hook phone/desktop push explicitly rejected.
  (D-008)
- **Delivery format** → a real table (Postgres in v1), not CSV files. (D-005)
- **Codex / AGENTS.md in v1** → no. (D-007)
