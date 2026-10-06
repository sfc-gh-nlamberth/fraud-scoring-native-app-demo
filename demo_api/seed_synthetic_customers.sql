-- Seeds 1,000 synthetic customers with alternating email/phone identifiers.
-- Run after mock_fraud_scorer.sql.

USE SCHEMA fraud_score_native_app_demo.demo_schema;

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
