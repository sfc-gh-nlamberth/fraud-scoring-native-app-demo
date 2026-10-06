# Fraud Scoring Native App Demo

A self-contained demo of a Snowflake Native App that scores customer records for
fraud risk. Scoring calls go to a mock stored-procedure "API" instead of a real
external fraud-scoring service, so this stands up entirely within one Snowflake
account/trial: no external endpoints, Docker, or SPCS required.

## What's in this repo

- `demo_api/`: the mock fraud-scoring API the app calls, plus synthetic sample
  data. In a real deployment this would be replaced by an actual external API
  (for example, called through an SPCS gateway + External Access Integration).
- `native_app/`: the Native App itself: `manifest.yml`, `setup.sql`, and a
  Streamlit UI (Setup wizard, Dashboard, Settings).
- `snowflake.yml`: project definition for the Snowflake CLI, if you prefer
  `snow app run` over the Snowsight workspace path below.

## Prerequisites

- A Snowflake account/trial with `ACCOUNTADMIN` (or a role with
  `CREATE APPLICATION PACKAGE`, `CREATE APPLICATION`, and `CREATE DATABASE` on
  the account) and a running warehouse.

## 1. Import this repo as a Git workspace in Snowsight

1. Sign in to Snowsight.
2. In the navigation menu, select **Projects » Workspaces**.
3. In the Workspaces menu, select **From Git repository**.
4. Paste this repo's URL into the **Repository URL** field:
   `https://github.com/sfc-gh-nlamberth/fraud-scoring-native-app-demo`
5. Under authentication, select **Public repository** (this repo is public,
   so no API integration or credentials are required).
6. Select **Create**.

Snowsight clones the repo into a Git-synced workspace, and all the files below
are editable and runnable directly from that workspace.

## 2. Create the mock fraud-scoring API

In the workspace's file browser, open `demo_api/mock_fraud_scorer.sql`,
select a warehouse and role in the file's toolbar, then select all and run.
Repeat for `demo_api/seed_synthetic_customers.sql`.

This creates `fraud_score_native_app_demo.demo_schema` with:
- `synthetic_customers`: 1,000 rows with alternating email/phone identifiers,
  usable as a stand-in "customer table" for the app's Setup wizard.
- `mock_fraud_scorer(ARRAY)`: deterministic hash-based scorer the app calls.
- `score_synthetic_customers(NUMBER)`: optional driver to score the sample
  table directly, without going through the app.

## 3. Deploy the Native App from the workspace

Open a new SQL file in the same workspace and run:

```sql
CREATE APPLICATION PACKAGE IF NOT EXISTS fraud_app_pkg;
```

Then find the Git repository object backing this workspace (Snowsight creates
one automatically when the workspace was created):

```sql
SHOW GIT REPOSITORIES LIKE '%fraud%';
```

Use the resulting repository name to install the app directly from the
workspace's cloned files, no manual file upload required:

```sql
CREATE APPLICATION fraud_app
  FROM APPLICATION PACKAGE fraud_app_pkg
  USING '@<repository_name>/branches/main/native_app';
```

(If you'd rather use the Snowflake CLI locally instead of the workspace path,
run `snow app run` from the repo root; it uses `snowflake.yml` to do the
equivalent of the steps above.)

## 4. Grant the app access to the mock API

The app can't see objects outside itself by default:

```sql
GRANT USAGE ON DATABASE fraud_score_native_app_demo TO APPLICATION fraud_app;
GRANT USAGE ON SCHEMA fraud_score_native_app_demo.demo_schema TO APPLICATION fraud_app;
GRANT USAGE ON PROCEDURE fraud_score_native_app_demo.demo_schema.mock_fraud_scorer(ARRAY) TO APPLICATION fraud_app;
```

## 5. Open the app and run Setup

Open `fraud_app` in Snowsight (Apps), or go directly to the Streamlit UI
(`fraud_app.app_schema.fraud_scoring_ui`). In the **Setup** page:

1. Select `fraud_score_native_app_demo.demo_schema.synthetic_customers` (or
   any table of your own with email/phone identifiers) as the customer table.
2. Map the `identifier` column as the email or phone column.
3. Select **Score Now**.

Then check the **Dashboard** page for score distribution and run history.

## Notes

- This is a demo build: `mock_fraud_scorer` is a deterministic hash of the
  identifier, not a real fraud model.
- `run_scoring()` re-scans the full table each run (skipping already-scored
  identifiers); there's no incremental stream/task pipeline in this version.
- See `native_app/README.md` for architecture details and known limitations.
