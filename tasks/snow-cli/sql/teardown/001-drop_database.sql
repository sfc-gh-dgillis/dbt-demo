USE ROLE sysadmin;

-- -----------------------------------------------------------------------
-- Drop the demo database
--
-- Reverses 003-create_db_schema.sql. Dropping the database cascades to the
-- raw, curated, modeled, and utilities schemas and every table, view, and
-- UDF they contain (including the utilities UDFs created by the dbt
-- run-operation tasks).
-- -----------------------------------------------------------------------
DROP DATABASE IF EXISTS dev_dbt_demo;

SHOW DATABASES LIKE 'dev_dbt_demo';
