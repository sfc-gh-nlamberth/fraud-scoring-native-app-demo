"""Setup wizard: permissions -> table selection -> column mapping -> run."""

import streamlit as st
import snowflake.permissions as permissions
from snowflake.snowpark.context import get_active_session
from utils.style import inject_theme

inject_theme()

st.title("📋 Setup")

session = get_active_session()

# ---------------------------------------------------------------------------
# Step 1: Select customer table
# ---------------------------------------------------------------------------
st.subheader("1. Select Your Customer Table")

table_refs = permissions.get_reference_associations("consumer_customer_table")
if table_refs:
    st.write(f"Currently selected: `{table_refs[0]}`")
else:
    st.write("No table selected yet.")

if st.button("Select Table"):
    permissions.request_reference("consumer_customer_table")

st.divider()

# ---------------------------------------------------------------------------
# Step 2: Column mapping
# ---------------------------------------------------------------------------
st.subheader("2. Map Your Columns")

existing = {
    r["KEY"]: r["VALUE"]
    for r in session.sql("SELECT key, value FROM app_schema.app_config").collect()
}

if table_refs:
    columns = [
        r["name"]
        for r in session.sql(
            "DESCRIBE TABLE REFERENCE('consumer_customer_table')"
        ).collect()
    ]
    options = ["(none)"] + columns

    email_col = st.selectbox(
        "Email column", options,
        index=options.index(existing.get("email_column", "(none)"))
        if existing.get("email_column", "(none)") in options else 0,
    )
    phone_col = st.selectbox(
        "Phone column", options,
        index=options.index(existing.get("phone_column", "(none)"))
        if existing.get("phone_column", "(none)") in options else 0,
    )
    id_col = st.selectbox(
        "Unique ID column (for joining results back)", options,
        index=options.index(existing.get("id_column", "(none)"))
        if existing.get("id_column", "(none)") in options else 0,
    )

    if st.button("Save Column Mapping"):
        for key, value in [
            ("email_column", email_col),
            ("phone_column", phone_col),
            ("id_column", id_col),
        ]:
            session.sql(
                """
                MERGE INTO app_schema.app_config t
                USING (SELECT ? AS key, ? AS value) s
                ON t.key = s.key
                WHEN MATCHED THEN UPDATE SET value = s.value
                WHEN NOT MATCHED THEN INSERT (key, value) VALUES (s.key, s.value)
                """,
                params=[key, value],
            ).collect()
        st.success("Column mapping saved.")
else:
    st.info("Select a table above before mapping columns.")

st.divider()

# ---------------------------------------------------------------------------
# Step 3: Score
# ---------------------------------------------------------------------------
st.subheader("3. Score Your Customers")
st.caption("v1 scores every row in your table each time you run it, skipping "
           "identifiers that are already scored.")

if st.button("🚀 Score Now"):
    with st.spinner("Scoring..."):
        result = session.call("app_schema.run_scoring")
    st.success(result)
    session.sql(
        """
        MERGE INTO app_schema.app_config t
        USING (SELECT 'setup_complete' AS key, 'true' AS value) s
        ON t.key = s.key
        WHEN MATCHED THEN UPDATE SET value = s.value
        WHEN NOT MATCHED THEN INSERT (key, value) VALUES (s.key, s.value)
        """
    ).collect()
