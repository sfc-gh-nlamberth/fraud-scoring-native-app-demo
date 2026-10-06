# Fraud Scoring Native App Demo

A self-contained demo of a Snowflake Native App that scores customer records for
fraud risk. Scoring calls go to a mock stored-procedure "API" instead of a real
external fraud-scoring service, so this stands up entirely within one Snowflake
account/trial: no external endpoints, Docker, or SPCS required.

## What's in this repo

- `00_create_role.sql`: creates a demo role and warehouse named `FRAUD_ROLE`
  with every privilege needed to run `01_setup.sql` and the Native App.
- `01_setup.sql`: creates the mock fraud-scoring API and synthetic sample
  data, deploys the Native App directly from this repo's public GitHub URL,
  and grants the app access to the mock API. In a real deployment the mock
  API would be replaced by an actual external API (for example, called
  through an SPCS gateway + External Access Integration).
- `demo_api/`: source for the mock fraud-scoring API and synthetic sample
  data, inlined into `01_setup.sql` for convenience.
- `native_app/`: the Native App itself: `manifest.yml`, `setup.sql`, and a
  Streamlit UI (Setup wizard, Dashboard, Settings).

## Prerequisites

- A Snowflake account/trial with `ACCOUNTADMIN` (or a role with `CREATE ROLE`,
  `CREATE WAREHOUSE`, `MANAGE GRANTS`, `CREATE DATABASE`,
  `CREATE APPLICATION PACKAGE`, `CREATE APPLICATION`, and
  `CREATE API INTEGRATION` on the account).

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

## 2. Create the demo role and warehouse

Open `00_create_role.sql` in the workspace, select all, and run it as
`ACCOUNTADMIN`. This creates the `FRAUD_ROLE` role and warehouse, grants the
role everything used in the rest of this guide, and grants the role to your
current user.

Switch to the role for every step from here on:

```sql
USE ROLE FRAUD_ROLE;
```

## 3. Run the setup script

Open `01_setup.sql` in the workspace, select all, and run it as `FRAUD_ROLE`.
This single script:

- Creates `fraud_score_native_app_demo.demo_schema` with:
  - `synthetic_customers`: 1,000 rows with alternating email/phone
    identifiers, usable as a stand-in "customer table" for the app's Setup
    wizard.
  - `mock_fraud_scorer(ARRAY)`: deterministic hash-based scorer the app
    calls.
  - `score_synthetic_customers(NUMBER)`: optional driver to score the
    sample table directly, without going through the app.
- Creates an API integration and a Git repository object pointing directly
  at this repo's public URL
  (`https://github.com/sfc-gh-nlamberth/fraud-scoring-native-app-demo`), with
  no dependency on the Git-synced workspace from step 1.
- Creates the application package and installs `fraud_app` from
  `native_app/` in that repository.
- Grants `fraud_app` `USAGE` on the database, schema, and
  `mock_fraud_scorer` procedure, so the app can call the mock API.

## 4. Open the app and run Setup

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
