"""Router: send partners to the setup wizard until configured, then the dashboard."""

import streamlit as st
from snowflake.snowpark.context import get_active_session
from utils.style import inject_theme

st.set_page_config(page_title="Fraud Scoring", page_icon="🛡️", layout="wide")
inject_theme()

session = get_active_session()


def is_configured():
    rows = session.sql(
        "SELECT value FROM app_schema.app_config WHERE key = 'setup_complete'"
    ).collect()
    return len(rows) > 0 and rows[0]["VALUE"] == "true"


st.title("🛡️ Fraud Scoring")
st.caption("Demo build: scoring calls go to the mock fraud-scorer stored procedure "
           "instead of the provider's SPCS gateway.")

if is_configured():
    st.info("Setup is complete. Use the pages in the sidebar: **Dashboard** to monitor "
            "scoring runs, **Settings** to change table/column mapping or schedule.")
else:
    st.warning("Setup is not complete yet. Open the **Setup** page in the sidebar to get started.")
