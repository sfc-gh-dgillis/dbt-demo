USE ROLE useradmin;

-- -----------------------------------------------------------------------
-- Drop the demo roles
--
-- Reverses 002-init_roles.sql. Functional roles are dropped before the
-- access roles they were granted. Dropping a role also removes its grants,
-- including the ROLE-to-USER grant made in 004-grants.sql.
--
-- Run 001 and 002 first so no dropped role still owns the database or a
-- warehouse.
-- -----------------------------------------------------------------------

-- functional roles
DROP ROLE IF EXISTS dbt_demo_data_engineer;
DROP ROLE IF EXISTS dbt_demo_analyst;

-- access roles
DROP ROLE IF EXISTS dbt_demo_rw;
DROP ROLE IF EXISTS dbt_demo_ro;

SHOW ROLES LIKE 'dbt_demo_%';
