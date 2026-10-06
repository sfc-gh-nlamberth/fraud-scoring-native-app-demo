# Fraud Scoring — Native App (Docker-free Demo, v1)

This is a demo variant of the architecture in
[`native-app-architecture.md`](../native-app-architecture.md).
Instead of the SPCS gateway/client containers + External Access Integration,
scoring calls go directly to the `mock_fraud_scorer` stored procedure in
`fraud_score_native_app_demo.demo_schema` (built for `fraud_api_native_app-8ac`).
No Docker, SPCS, or EAI is required.

v1 also skips the stream/task incremental-CDC pipeline: `run_scoring()`
simply scans every row currently in the referenced customer table and skips
identifiers it has already scored. A stream/task for true incremental
scoring can be layered on later (see "Not included" below).

## What it does

1. Reads every row from the consumer's customer table (bound via the
   `consumer_customer_table` reference).
2. For each row with an email or phone identifier not already in
   `app_schema.fraud_scores`, calls
   `fraud_score_native_app_demo.demo_schema.mock_fraud_scorer` to get a
   deterministic mock fraud score.
3. Writes results to `app_schema.fraud_scores` (joinable via
   `app_schema.fraud_scores_view`).
4. A Streamlit UI (Setup / Dashboard / Settings) lets partners pick their
   table, map columns, and trigger scoring runs — no SQL required.

## Deploying

From `native_app/`, using the Snowflake CLI:

```bash
snow app run
```

This creates the application package, uploads artifacts, and installs the
app in the current connection's account.

If `snow app run` isn't usable (e.g. stale CLI session token), the app can be
deployed manually via SQL (run `../00_create_role.sql` first, then use that
role here):

```sql
USE ROLE fraud_demo_role;

CREATE APPLICATION PACKAGE IF NOT EXISTS fraud_app_pkg;
CREATE SCHEMA IF NOT EXISTS fraud_app_pkg.app_src;
CREATE STAGE IF NOT EXISTS fraud_app_pkg.app_src.stage;
-- PUT each file (manifest.yml, setup.sql, README.md, streamlit/**) onto the stage,
-- preserving the streamlit/ directory structure, then:
CREATE APPLICATION fraud_app
  FROM APPLICATION PACKAGE fraud_app_pkg
  USING '@fraud_app_pkg.app_src.stage';
```

Since this demo runs in a single account, the app's `run_scoring` proc calls
`fraud_score_native_app_demo.demo_schema.mock_fraud_scorer` directly by
fully-qualified name — in a real cross-account deployment this call would
instead go through the SPCS gateway described in the main architecture doc.

### Required grants (same-account demo only)

Because the mock scorer lives outside the application, the app needs
explicit access to it (Native Apps can't see objects outside themselves or
their references by default):

```sql
USE ROLE fraud_demo_role;

GRANT USAGE ON DATABASE fraud_score_native_app_demo TO APPLICATION fraud_app;
GRANT USAGE ON SCHEMA fraud_score_native_app_demo.demo_schema TO APPLICATION fraud_app;
GRANT USAGE ON PROCEDURE fraud_score_native_app_demo.demo_schema.mock_fraud_scorer(ARRAY) TO APPLICATION fraud_app;
```

### Binding the customer table reference

The consumer's table must have `CHANGE_TRACKING` supportable metadata (no
stream is created in v1, so this isn't strictly required, but keeping it
consistent with future stream/task versions is recommended). Bind the
reference and set the column mapping:

```sql
USE ROLE fraud_demo_role;

CALL fraud_app.app_schema.register_table_callback(
  'consumer_customer_table', 'ADD',
  SYSTEM$REFERENCE('TABLE', '<db>.<schema>.<table>', 'PERSISTENT', 'SELECT')
);

INSERT INTO fraud_app.app_schema.app_config (key, value) VALUES
  ('email_column', '<EMAIL_COL>'),
  ('phone_column', '<PHONE_COL_OR_(none)>'),
  ('id_column', '<ID_COL>');

CALL fraud_app.app_schema.run_scoring();
```

## Prerequisites

- `../00_create_role.sql` has been run, and you're using the resulting
  `fraud_demo_role` for the deployment statements below.
- `fraud_score_native_app_demo.demo_schema.mock_fraud_scorer` must already
  exist (see `../procs/mock_fraud_scorer.sql`).
- A customer table with an email and/or phone column to bind as
  `consumer_customer_table` (e.g. `../procs/synthetic_customers.sql`, using
  the `identifier`/`identifier_type` columns as a stand-in).

## Known limitations (v1)

- **Performance**: `run_scoring()` calls the mock scorer one identifier at a
  time (matching the existing `score_synthetic_customers` driver pattern).
  For ~1000 rows this can take several minutes. A future version should
  batch calls or reintroduce a stream/task for incremental-only scoring.
- No incremental change detection — every run re-scans the full table
  (though already-scored identifiers are skipped, not re-scored).

## Not included (out of scope for the demo)

- `client/`, `gateway/`, `mock_api/` SPCS containers, Dockerfiles, and the
  External Access Integration wiring described in the main architecture doc.
- Streams/tasks for incremental scoring (deferred from v1 for simplicity —
  see "Known limitations").
