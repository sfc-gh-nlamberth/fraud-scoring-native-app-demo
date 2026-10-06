-- Mock fraud-scoring API: stands in for a real external fraud-scoring service.
-- Run this once in a trial account before deploying the Native App (native_app/).
-- Run 00_create_role.sql first and use the same name here.

SET demo_name = '<YOUR_NAME>'; -- same name used in 00_create_role.sql
USE ROLE IDENTIFIER($demo_name);
USE WAREHOUSE IDENTIFIER($demo_name);

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
