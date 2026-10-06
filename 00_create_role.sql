-- Step 00: creates a role with every privilege required to run the scripts in
-- demo_api/ and the deployment statements in native_app/.
--
-- Run this once, as ACCOUNTADMIN (or a role with CREATE ROLE, MANAGE GRANTS,
-- and the privileges granted below), before running anything else in this repo.

SET demo_role_name = 'FRAUD_DEMO_ROLE';
SET demo_warehouse_name = '<YOUR_WAREHOUSE_NAME>'; -- replace with an existing warehouse
SET demo_user_name = CURRENT_USER();

CREATE ROLE IF NOT EXISTS IDENTIFIER($demo_role_name)
  COMMENT = 'Runs the fraud-scoring-native-app-demo scripts (demo_api/ and native_app/).';

-- demo_api/: lets the role create fraud_score_native_app_demo and everything
-- inside it (schema, table, procs); ownership of the database carries the
-- privileges needed for the schema/table/procedure DDL in that folder.
GRANT CREATE DATABASE ON ACCOUNT TO ROLE IDENTIFIER($demo_role_name);

-- native_app/: lets the role create and install the Native App. Ownership of
-- the resulting application package/application carries the privileges
-- needed to grant the mock API's USAGE grants to the installed app.
GRANT CREATE APPLICATION PACKAGE ON ACCOUNT TO ROLE IDENTIFIER($demo_role_name);
GRANT CREATE APPLICATION ON ACCOUNT TO ROLE IDENTIFIER($demo_role_name);

-- warehouse to run the SQL/Python statements in both folders
GRANT USAGE, OPERATE ON WAREHOUSE IDENTIFIER($demo_warehouse_name) TO ROLE IDENTIFIER($demo_role_name);

-- let the current user switch into the role
GRANT ROLE IDENTIFIER($demo_role_name) TO USER IDENTIFIER($demo_user_name);
