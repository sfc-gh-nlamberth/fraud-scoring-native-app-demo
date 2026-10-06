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

See the root [`README.md`](../README.md) for the recommended deployment
path: import this repo as a Git workspace in Snowsight, then run
`00_create_role.sql`, `demo_api/`, and the `CREATE APPLICATION PACKAGE` /
`CREATE APPLICATION` statements directly from the workspace.

Since this demo runs in a single account, the app's `run_scoring` proc calls
`fraud_score_native_app_demo.demo_schema.mock_fraud_scorer` directly by
fully-qualified name — in a real cross-account deployment this call would
instead go through the SPCS gateway described in the main architecture doc.

### Required grants (same-account demo only)

Because the mock scorer lives outside the application, the app needs
explicit access to it (Native Apps can't see objects outside themselves or
their references by default):

```sql
SET demo_name = '<YOUR_NAME>'; -- same name used in 00_create_role.sql
USE ROLE IDENTIFIER($demo_name);

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
SET demo_name = '<YOUR_NAME>'; -- same name used in 00_create_role.sql
USE ROLE IDENTIFIER($demo_name);

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

- `../00_create_role.sql` has been run, and you're using the resulting role
  (the name you chose) for the deployment statements below.
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
