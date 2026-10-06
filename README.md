# Fraud Scoring Native App — Demo

A self-contained demo of a Snowflake Native App that scores customer records for
fraud risk. Scoring calls go to a mock stored-procedure "API" instead of a real
external fraud-scoring service, so this stands up entirely within one Snowflake
account/trial — no external endpoints, Docker, or SPCS required.

## What's in this repo

- `demo_api/` — the mock fraud-scoring API the app calls, plus synthetic sample
  data. In a real deployment this would be replaced by an actual external API
  (e.g. called through an SPCS gateway + External Access Integration).
- `native_app/` — the Native App itself: `manifest.yml`, `setup.sql`, and a
  Streamlit UI (Setup wizard / Dashboard / Settings).
- `snowflake.yml` — project definition so `snow app run` can deploy everything
  with one command.

## Prerequisites

- A Snowflake account/trial with `ACCOUNTADMIN` (or a role with
  `CREATE APPLICATION PACKAGE` / `CREATE APPLICATION` / `CREATE DATABASE` on
  account) and a running warehouse.
- (Recommended) [Snowflake CLI](https://docs.snowflake.com/en/developer-guide/snowflake-cli/installation/installation)
  (`snow`) v3+, with a connection configured (`snow connection add`).

## 1. Create the mock fraud-scoring API

Run these against your account (Snowsight worksheet, SnowSQL, or `snow sql -f`):

```bash
snow sql -f demo_api/mock_fraud_scorer.sql
snow sql -f demo_api/seed_synthetic_customers.sql
```

This creates `fraud_score_native_app_demo.demo_schema` with:
- `synthetic_customers` — 1,000 rows with alternating email/phone identifiers,
  usable as a stand-in "customer table" for the app's Setup wizard.
- `mock_fraud_scorer(ARRAY)` — deterministic hash-based scorer the app calls.
- `score_synthetic_customers(NUMBER)` — optional driver to score the sample
  table directly, without going through the app.

## 2. Deploy the Native App

**Option A — Snowflake CLI (recommended):**

```bash
snow app run
```

This creates the application package and installs the app in your account
using `snowflake.yml`.

**Option B — Manual SQL** (see `native_app/README.md` for the full manual
deploy path, including uploading `native_app/streamlit/**` to a stage).

## 3. Grant the app access to the mock API

The app can't see objects outside itself by default:

```sql
GRANT USAGE ON DATABASE fraud_score_native_app_demo TO APPLICATION fraud_app;
GRANT USAGE ON SCHEMA fraud_score_native_app_demo.demo_schema TO APPLICATION fraud_app;
GRANT USAGE ON PROCEDURE fraud_score_native_app_demo.demo_schema.mock_fraud_scorer(ARRAY) TO APPLICATION fraud_app;
```

## 4. Open the app and run Setup

Open `fraud_app` in Snowsight (Apps), or go directly to the Streamlit UI
(`fraud_app.app_schema.fraud_scoring_ui`). In the **Setup** page:

1. Select `fraud_score_native_app_demo.demo_schema.synthetic_customers` (or
   any table of your own with email/phone identifiers) as the customer table.
2. Map the `identifier` column as the email or phone column.
3. Click **Score Now**.

Then check the **Dashboard** page for score distribution and run history.

## Notes

- This is a demo build: `mock_fraud_scorer` is a deterministic hash of the
  identifier, not a real fraud model.
- `run_scoring()` re-scans the full table each run (skipping already-scored
  identifiers) — there's no incremental stream/task pipeline in this version.
- See `native_app/README.md` for architecture details, known limitations, and
  the manual (non-CLI) deployment path.
