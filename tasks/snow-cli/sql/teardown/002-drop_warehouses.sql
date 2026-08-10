USE ROLE sysadmin;

-- -----------------------------------------------------------------------
-- Drop the demo warehouses
--
-- Reverses 001-create_warehouses.sql. Dropping a warehouse also removes the
-- USAGE grants made to dbt_demo_rw in 004-grants.sql.
-- -----------------------------------------------------------------------
DROP WAREHOUSE IF EXISTS dbt_demo_xs_wh;
DROP WAREHOUSE IF EXISTS dbt_demo_s_wh;
DROP WAREHOUSE IF EXISTS dbt_demo_m_wh;
DROP WAREHOUSE IF EXISTS dbt_demo_l_wh;
DROP WAREHOUSE IF EXISTS dbt_demo_xl_wh;
DROP WAREHOUSE IF EXISTS dbt_demo_xxl_wh;

SHOW WAREHOUSES LIKE 'dbt_demo_%';
