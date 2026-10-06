# Fraud Scoring Native App Demo

## What it does

1. Reads every row from the consumer's customer table (bound via the
   `consumer_customer_table` reference).
2. For each row with an email or phone identifier not already in
   `app_schema.fraud_scores`, calls
   `fraud_score_native_app_demo.demo_schema.mock_fraud_scorer` to get a
   deterministic mock fraud score.
3. Writes results to `app_schema.fraud_scores` (joinable via
   `app_schema.fraud_scores_view`).
4. A Streamlit UI (Setup / Dashboard / Settings) lets partners pick their
   table, map columns, and trigger scoring runs — no SQL required.
