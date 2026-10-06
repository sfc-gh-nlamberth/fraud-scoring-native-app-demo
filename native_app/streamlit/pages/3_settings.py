"""Settings: reconfigure table/column mapping."""

import streamlit as st
import snowflake.permissions as permissions
from snowflake.snowpark.context import get_active_session
from utils.style import inject_theme

inject_theme()

st.title("⚙️ Settings")

session = get_active_session()

st.subheader("Reconfigure Customer Table")
if st.button("Change Table"):
    permissions.request_reference("consumer_customer_table")

st.divider()

st.subheader("Current Configuration")
config_df = session.sql("SELECT key, value FROM app_schema.app_config ORDER BY key").to_pandas()
st.dataframe(config_df, use_container_width=True)
