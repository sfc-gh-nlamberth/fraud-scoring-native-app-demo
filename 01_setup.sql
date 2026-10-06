-- Step 01: creates the mock fraud-scoring API, deploys the Native App from
-- this repo's public GitHub URL, and grants the app access to the mock API.
--
-- Run 00_create_role.sql first (as ACCOUNTADMIN), then run this script as
-- FRAUD_ROLE.

USE ROLE FRAUD_ROLE;
USE WAREHOUSE FRAUD_ROLE;

-- =============================================================================
-- Part 1: Mock fraud-scoring API (formerly demo_api/mock_fraud_scorer.sql)
-- =============================================================================
-- Stands in for a real external fraud-scoring service.

CREATE DATABASE IF NOT EXISTS fraud_score_native_app_demo;
CREATE SCHEMA IF NOT EXISTS fraud_score_native_app_demo.demo_schema;

USE SCHEMA fraud_score_native_app_demo.demo_schema;

CREATE OR REPLACE TABLE synthetic_customers (
    customer_id NUMBER(11,0),
    identifier VARCHAR,
    identifier_type VARCHAR(5),
    last_score_result VARIANT,
    last_scored_at TIMESTAMP_NTZ
);

-- Deterministic mock scorer: hashes each identifier to a stable 0-1 "fraud score".
-- Swap this out for a real external call (e.g. via External Access Integration /
-- SPCS gateway) in a production deployment.
CREATE OR REPLACE PROCEDURE mock_fraud_scorer(identifiers ARRAY)
RETURNS VARIANT
LANGUAGE PYTHON
RUNTIME_VERSION = '3.11'
PACKAGES = ('snowflake-snowpark-python')
HANDLER = 'score'
EXECUTE AS OWNER
AS
$$
import hashlib

def score(session, identifiers):
    results = []
    for item in identifiers:
        value = item['value']
        id_type = item['type']
        hash_val = int(hashlib.md5(value.encode()).hexdigest(), 16)
        fraud_score = round((hash_val % 10000) / 10000.0, 4)
        results.append({
            "identifier": value,
            "identifier_type": id_type,
            "fraud_score": fraud_score,
            "model_version": "mock-v1.0"
        })
    return {"scores": results}
$$;

-- Optional convenience driver: scores synthetic_customers directly (outside the
-- Native App), useful for exercising the mock API without the Streamlit UI.
CREATE OR REPLACE PROCEDURE score_synthetic_customers(batch_size NUMBER)
RETURNS VARCHAR
LANGUAGE PYTHON
RUNTIME_VERSION = '3.11'
PACKAGES = ('snowflake-snowpark-python')
HANDLER = 'run'
EXECUTE AS OWNER
AS
$$
import json

def run(session, batch_size):
    rows = session.sql(f"""
        SELECT customer_id, identifier, identifier_type
        FROM fraud_score_native_app_demo.demo_schema.synthetic_customers
        WHERE last_score_result IS NULL
        ORDER BY customer_id
        LIMIT {batch_size}
    """).collect()

    scored = 0
    for row in rows:
        result = session.call(
            "fraud_score_native_app_demo.demo_schema.mock_fraud_scorer",
            [{"value": row["IDENTIFIER"], "type": row["IDENTIFIER_TYPE"]}]
        )
        session.sql(
            """
            UPDATE fraud_score_native_app_demo.demo_schema.synthetic_customers
            SET last_score_result = PARSE_JSON(?), last_scored_at = CURRENT_TIMESTAMP()
            WHERE customer_id = ?
            """,
            params=[json.dumps(result), row["CUSTOMER_ID"]]
        ).collect()
        scored += 1

    return f"scored {scored} customers"
$$;

-- =============================================================================
-- Part 2: Seed synthetic customers (formerly demo_api/seed_synthetic_customers.sql)
-- =============================================================================
-- Seeds 1,000 synthetic customers with alternating email/phone identifiers.

INSERT INTO synthetic_customers (customer_id, identifier, identifier_type)
SELECT
    seq4() + 1 AS customer_id,
    CASE
        WHEN MOD(seq4(), 2) = 0 THEN 'user' || (seq4() + 1) || '@example.com'
        ELSE '+1555' || LPAD((2000000 + seq4())::VARCHAR, 7, '0')
    END AS identifier,
    CASE WHEN MOD(seq4(), 2) = 0 THEN 'email' ELSE 'phone' END AS identifier_type
FROM TABLE(GENERATOR(ROWCOUNT => 1000))
ORDER BY 1;

-- =============================================================================
-- Part 3: Deploy the Native App directly from this repo's public GitHub URL
-- (formerly README step 4; no workspace Git repository lookup required)
-- =============================================================================

CREATE API INTEGRATION IF NOT EXISTS fraud_demo_github_api_integration
  API_PROVIDER = GIT_HTTPS_API
  API_ALLOWED_PREFIXES = ('https://github.com/sfc-gh-nlamberth/fraud-scoring-native-app-demo')
  ENABLED = TRUE
  COMMENT = 'Allows FRAUD_ROLE to clone the public fraud-scoring-native-app-demo repo.';

CREATE GIT REPOSITORY IF NOT EXISTS fraud_scoring_native_app_demo_repo
  API_INTEGRATION = fraud_demo_github_api_integration
  ORIGIN = 'https://github.com/sfc-gh-nlamberth/fraud-scoring-native-app-demo';

ALTER GIT REPOSITORY fraud_scoring_native_app_demo_repo FETCH;

CREATE APPLICATION PACKAGE IF NOT EXISTS fraud_app_pkg;

CREATE APPLICATION fraud_app
  FROM APPLICATION PACKAGE fraud_app_pkg
  USING '@fraud_score_native_app_demo.demo_schema.fraud_scoring_native_app_demo_repo/branches/main/native_app';

-- =============================================================================
-- Part 4: Grant the app access to the mock API (formerly README step 5)
-- =============================================================================
-- The app can't see objects outside itself by default.

GRANT USAGE ON DATABASE fraud_score_native_app_demo TO APPLICATION fraud_app;
GRANT USAGE ON SCHEMA fraud_score_native_app_demo.demo_schema TO APPLICATION fraud_app;
GRANT USAGE ON PROCEDURE fraud_score_native_app_demo.demo_schema.mock_fraud_scorer(ARRAY) TO APPLICATION fraud_app;
