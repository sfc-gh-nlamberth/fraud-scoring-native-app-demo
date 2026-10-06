"""Operational dashboard: metrics, manual trigger, score distribution, run history."""

import streamlit as st
from snowflake.snowpark.context import get_active_session
from utils.style import inject_theme

inject_theme()

st.title("🛡️ Fraud Scoring Dashboard")

session = get_active_session()

total_scored = session.sql("SELECT COUNT(*) AS n FROM app_schema.fraud_scores").collect()[0]["N"]
high_risk = session.sql(
    "SELECT COUNT(*) AS n FROM app_schema.fraud_scores WHERE fraud_score >= 0.8"
).collect()[0]["N"]
avg_score_row = session.sql("SELECT AVG(fraud_score) AS avg_score FROM app_schema.fraud_scores").collect()
avg_score = avg_score_row[0]["AVG_SCORE"] if avg_score_row and avg_score_row[0]["AVG_SCORE"] is not None else 0.0

last_run_rows = session.sql(
    "SELECT * FROM app_schema.run_history ORDER BY run_at DESC LIMIT 1"
).collect()

col1, col2, col3 = st.columns(3)
col1.metric("Total Scored", f"{total_scored:,}")
pct = f"{(high_risk / total_scored * 100):.1f}%" if total_scored else "0%"
col2.metric("High Risk", f"{high_risk:,}", pct)
col3.metric("Avg Score", f"{avg_score:.2f}")

if last_run_rows:
    lr = last_run_rows[0]
    st.caption(f"Last run: {lr['RUN_AT']} — {lr['STATUS']} — {lr['MESSAGE']}")
else:
    st.caption("No runs yet.")

st.divider()

if st.button("🔄 Run Now"):
    with st.spinner("Scoring..."):
        result = session.call("app_schema.run_scoring")
    st.success(result)
    st.rerun()

st.divider()

st.subheader("Score Distribution")
dist = session.sql(
    """
    SELECT
        CASE
            WHEN fraud_score < 0.2 THEN '0.0-0.2'
            WHEN fraud_score < 0.4 THEN '0.2-0.4'
            WHEN fraud_score < 0.6 THEN '0.4-0.6'
            WHEN fraud_score < 0.8 THEN '0.6-0.8'
            ELSE '0.8-1.0'
        END AS bucket,
        COUNT(*) AS n
    FROM app_schema.fraud_scores
    GROUP BY 1
    ORDER BY 1
    """
).to_pandas()
if not dist.empty:
    st.bar_chart(dist.set_index("BUCKET"))
else:
    st.info("No scores yet.")

st.divider()

st.subheader("Recent High-Risk")
high_risk_df = session.sql(
    """
    SELECT identifier, source_id, fraud_score, scored_at
    FROM app_schema.fraud_scores
    WHERE fraud_score >= 0.8
    ORDER BY scored_at DESC
    LIMIT 10
    """
).to_pandas()
st.dataframe(high_risk_df, use_container_width=True)

st.divider()

st.subheader("Run History")
history_df = session.sql(
    "SELECT run_at, status, total_rows, scored, message FROM app_schema.run_history ORDER BY run_at DESC LIMIT 20"
).to_pandas()
st.dataframe(history_df, use_container_width=True)

st.divider()

st.subheader("How to Use Results")
st.code(
    """SELECT c.*, f.fraud_score, f.risk_category
FROM your_db.your_schema.customers c
LEFT JOIN fraud_app.app_schema.fraud_scores_view f
    ON c.email = f.identifier OR c.phone = f.identifier;""",
    language="sql",
)
