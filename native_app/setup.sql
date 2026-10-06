-- Fraud Scoring Native App — setup script (Docker-free demo variant, v1)
--
-- This variant skips the SPCS gateway/client containers, EAI, and the
-- stream/task incremental-CDC pipeline entirely. v1 simply scores every row
-- in the referenced customer table against
-- fraud_score_native_app_demo.demo_schema.mock_fraud_scorer (the stand-in for
-- the provider's on-prem fraud API + SPCS gateway) each time it's run, skipping
-- identifiers already scored. No Docker, SPCS, EAI, streams, or tasks.

CREATE APPLICATION ROLE IF NOT EXISTS app_user;

CREATE SCHEMA IF NOT EXISTS app_schema;
GRANT USAGE ON SCHEMA app_schema TO APPLICATION ROLE app_user;

-- ---------------------------------------------------------------------------
-- Results + config tables
-- ---------------------------------------------------------------------------

CREATE TABLE IF NOT EXISTS app_schema.fraud_scores (
    identifier       STRING        NOT NULL,
    identifier_type  STRING        NOT NULL,   -- 'email' or 'phone'
    fraud_score      FLOAT         NOT NULL,   -- 0.0 (low risk) to 1.0 (high risk)
    source_id        STRING,                    -- partner's original ID for joining
    model_version    STRING,
    scored_at        TIMESTAMP_NTZ DEFAULT CURRENT_TIMESTAMP(),
    PRIMARY KEY (identifier)
);

CREATE TABLE IF NOT EXISTS app_schema.app_config (
    key   STRING PRIMARY KEY,
    value STRING
);

CREATE TABLE IF NOT EXISTS app_schema.run_history (
    run_at      TIMESTAMP_NTZ DEFAULT CURRENT_TIMESTAMP(),
    status      STRING,
    total_rows  INTEGER,
    scored      INTEGER,
    message     STRING
);

CREATE OR REPLACE SECURE VIEW app_schema.fraud_scores_view AS
SELECT
    identifier,
    identifier_type,
    source_id,
    fraud_score,
    CASE
        WHEN fraud_score >= 0.8 THEN 'HIGH'
        WHEN fraud_score >= 0.4 THEN 'MEDIUM'
        ELSE 'LOW'
    END AS risk_category,
    model_version,
    scored_at
FROM app_schema.fraud_scores;

GRANT SELECT ON TABLE app_schema.fraud_scores TO APPLICATION ROLE app_user;
GRANT SELECT, INSERT, UPDATE, DELETE ON TABLE app_schema.app_config TO APPLICATION ROLE app_user;
GRANT SELECT ON TABLE app_schema.run_history TO APPLICATION ROLE app_user;
GRANT SELECT ON VIEW app_schema.fraud_scores_view TO APPLICATION ROLE app_user;

-- ---------------------------------------------------------------------------
-- Scoring proc — reads every row from the referenced customer table, skips
-- identifiers already scored, calls the mock fraud scorer, writes results.
-- ---------------------------------------------------------------------------

CREATE OR REPLACE PROCEDURE app_schema.run_scoring()
RETURNS STRING
LANGUAGE PYTHON
RUNTIME_VERSION = '3.11'
PACKAGES = ('snowflake-snowpark-python')
HANDLER = 'run'
AS
$$
MOCK_SCORER = "fraud_score_native_app_demo.demo_schema.mock_fraud_scorer"

import json
from snowflake.snowpark.functions import when_matched, when_not_matched, current_timestamp


def run(session):
    config = {r["KEY"]: r["VALUE"] for r in
              session.sql("SELECT key, value FROM app_schema.app_config").collect()}
    email_col = config.get("email_column")
    phone_col = config.get("phone_column")
    id_col = config.get("id_column")

    rows = session.sql("SELECT * FROM REFERENCE('consumer_customer_table')").collect()

    total_rows = len(rows)
    if total_rows == 0:
        session.sql("""
            INSERT INTO app_schema.run_history (status, total_rows, scored, message)
            VALUES ('SKIPPED', 0, 0, 'Customer table is empty')
        """).collect()
        return "Customer table is empty. Skipped."

    # Build the list of identifiers to (re)score (dedupe by identifier,
    # last row wins). Every run rescores every identifier, replacing any
    # previous score.
    to_score = {}
    for row in rows:
        d = row.as_dict()
        value = None
        id_type = None
        if email_col and d.get(email_col):
            value, id_type = d[email_col], "email"
        elif phone_col and d.get(phone_col):
            value, id_type = d[phone_col], "phone"

        if value is None:
            continue

        source_id = d.get(id_col, "") if id_col else ""
        to_score[value] = {"value": value, "type": id_type, "source_id": source_id}

    scored = 0
    items = list(to_score.values())
    BATCH_SIZE = 200
    for i in range(0, len(items), BATCH_SIZE):
        batch = items[i:i + BATCH_SIZE]
        result = session.call(
            MOCK_SCORER,
            [{"value": item["value"], "type": item["type"]} for item in batch],
        )
        if isinstance(result, str):
            result = json.loads(result)
        score_rows = result["scores"]

        merge_rows = [
            (
                score_row["identifier"],
                score_row["identifier_type"],
                score_row["fraud_score"],
                batch[j]["source_id"],
                score_row.get("model_version", ""),
            )
            for j, score_row in enumerate(score_rows)
        ]

        source_df = session.create_dataframe(
            merge_rows,
            schema=["identifier", "identifier_type", "fraud_score", "source_id", "model_version"],
        )
        target = session.table("app_schema.fraud_scores")
        target.merge(
            source_df,
            target["identifier"] == source_df["identifier"],
            [
                when_matched().update({
                    "fraud_score": source_df["fraud_score"],
                    "model_version": source_df["model_version"],
                    "scored_at": current_timestamp(),
                }),
                when_not_matched().insert({
                    "identifier": source_df["identifier"],
                    "identifier_type": source_df["identifier_type"],
                    "fraud_score": source_df["fraud_score"],
                    "source_id": source_df["source_id"],
                    "model_version": source_df["model_version"],
                    "scored_at": current_timestamp(),
                }),
            ],
        )
        scored += len(merge_rows)

    session.sql(
        "INSERT INTO app_schema.run_history (status, total_rows, scored, message) VALUES ('OK', ?, ?, ?)",
        params=[total_rows, scored, f"Scored {scored} identifiers out of {total_rows} rows"],
    ).collect()

    return f"Scored {scored} identifiers out of {total_rows} rows"
$$;

GRANT USAGE ON PROCEDURE app_schema.run_scoring() TO APPLICATION ROLE app_user;

-- ---------------------------------------------------------------------------
-- Streamlit UI
-- ---------------------------------------------------------------------------

CREATE STREAMLIT IF NOT EXISTS app_schema.fraud_scoring_ui
  FROM '/streamlit'
  MAIN_FILE = 'main.py';

GRANT USAGE ON STREAMLIT app_schema.fraud_scoring_ui TO APPLICATION ROLE app_user;

-- ---------------------------------------------------------------------------
-- Reference-registration callbacks (called by the Permission SDK from Streamlit)
-- ---------------------------------------------------------------------------

CREATE OR REPLACE PROCEDURE app_schema.register_table_callback(ref_name STRING, operation STRING, ref_or_alias STRING)
RETURNS STRING
LANGUAGE SQL
AS
$$
BEGIN
  CASE (operation)
    WHEN 'ADD' THEN
      SELECT SYSTEM$SET_REFERENCE(:ref_name, :ref_or_alias);
    WHEN 'REMOVE' THEN
      SELECT SYSTEM$REMOVE_REFERENCE(:ref_name, :ref_or_alias);
    WHEN 'CLEAR' THEN
      SELECT SYSTEM$REMOVE_ALL_REFERENCES(:ref_name);
    ELSE
      RETURN 'unknown operation: ' || :operation;
  END CASE;
  RETURN 'ok';
END;
$$;

GRANT USAGE ON PROCEDURE app_schema.register_table_callback(STRING, STRING, STRING) TO APPLICATION ROLE app_user;
