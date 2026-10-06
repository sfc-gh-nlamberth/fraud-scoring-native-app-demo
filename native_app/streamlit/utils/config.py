"""Helpers for reading/writing app_schema.app_config and registering references."""

from snowflake.snowpark.context import get_active_session


def get_session():
    return get_active_session()


def get_config():
    session = get_session()
    rows = session.sql("SELECT key, value FROM app_schema.app_config").collect()
    return {r["KEY"]: r["VALUE"] for r in rows}


def set_config(**kwargs):
    session = get_session()
    for key, value in kwargs.items():
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


def register_table_callback(ref_name, operation, ref_or_alias):
    session = get_session()
    return session.call("app_schema.register_table_callback", ref_name, operation, ref_or_alias)


def register_warehouse_callback(ref_name, operation, ref_or_alias):
    session = get_session()
    return session.call("app_schema.register_warehouse_callback", ref_name, operation, ref_or_alias)
