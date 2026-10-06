-- Step 00: creates a role and warehouse with every privilege required to run
-- the scripts in demo_api/ and the deployment statements in native_app/.
--
-- Run this once, as ACCOUNTADMIN (or a role with CREATE ROLE, CREATE WAREHOUSE,
-- MANAGE GRANTS, and the privileges granted below), before running anything
-- else in this repo.

USE ROLE ACCOUNTADMIN;
SET USER_NAME = CURRENT_USER();

CREATE ROLE IF NOT EXISTS FRAUD_DEMO
  COMMENT = 'Runs the fraud-scoring-native-app-demo scripts (demo_api/ and native_app/).';

CREATE WAREHOUSE IF NOT EXISTS FRAUD_DEMO
  WAREHOUSE_SIZE = 'XSMALL'
  AUTO_SUSPEND = 60
  AUTO_RESUME = TRUE
  COMMENT = 'Runs the SQL/Python statements for the fraud-scoring-native-app-demo scripts.';

-- demo_api/: lets the role create fraud_score_native_app_demo and everything
-- inside it (schema, table, procs); ownership of the database carries the
-- privileges needed for the schema/table/procedure DDL in that folder.
GRANT CREATE DATABASE ON ACCOUNT TO ROLE FRAUD_DEMO;

-- native_app/: lets the role create and install the Native App. Ownership of
-- the resulting application package/application carries the privileges
-- needed to grant the mock API's USAGE grants to the installed app.
GRANT CREATE APPLICATION PACKAGE ON ACCOUNT TO ROLE FRAUD_DEMO;
GRANT CREATE APPLICATION ON ACCOUNT TO ROLE FRAUD_DEMO;

-- warehouse to run the SQL/Python statements in both folders
GRANT USAGE, OPERATE ON WAREHOUSE FRAUD_DEMO TO ROLE FRAUD_DEMO;

-- let the current user switch into the role
GRANT ROLE FRAUD_DEMO TO USER IDENTIFIER($USER_NAME);
