-- Step 00: creates a role and warehouse with every privilege required to run
-- 01_setup.sql (mock API, Git-based Native App deployment) and native_app/.
--
-- Run this once, as ACCOUNTADMIN (or a role with CREATE ROLE, CREATE WAREHOUSE,
-- MANAGE GRANTS, and the privileges granted below), before running anything
-- else in this repo.

USE ROLE ACCOUNTADMIN;
SET USER_NAME = CURRENT_USER();

CREATE ROLE IF NOT EXISTS FRAUD_ROLE
  COMMENT = 'Runs the fraud-scoring-native-app-demo scripts (01_setup.sql and native_app/).';

CREATE WAREHOUSE IF NOT EXISTS FRAUD_ROLE
  WAREHOUSE_SIZE = 'XSMALL'
  AUTO_SUSPEND = 60
  AUTO_RESUME = TRUE
  COMMENT = 'Runs the SQL/Python statements for the fraud-scoring-native-app-demo scripts.';

-- 01_setup.sql (mock API): lets the role create fraud_score_native_app_demo
-- and everything inside it (schema, table, procs); ownership of the database
-- carries the privileges needed for the schema/table/procedure DDL.
GRANT CREATE DATABASE ON ACCOUNT TO ROLE FRAUD_ROLE;

-- 01_setup.sql (Git-based app deployment): lets the role create the API
-- integration and Git repository object used to pull native_app/ directly
-- from this repo's public GitHub URL, and create/install the Native App.
-- Ownership of the resulting application package/application carries the
-- privileges needed to grant the mock API's USAGE grants to the installed app.
GRANT CREATE API INTEGRATION ON ACCOUNT TO ROLE FRAUD_ROLE;
GRANT CREATE APPLICATION PACKAGE ON ACCOUNT TO ROLE FRAUD_ROLE;
GRANT CREATE APPLICATION ON ACCOUNT TO ROLE FRAUD_ROLE;

-- warehouse to run the SQL/Python statements in both folders
GRANT USAGE, OPERATE ON WAREHOUSE FRAUD_ROLE TO ROLE FRAUD_ROLE;

-- let the current user switch into the role
GRANT ROLE FRAUD_ROLE TO USER IDENTIFIER($USER_NAME);
