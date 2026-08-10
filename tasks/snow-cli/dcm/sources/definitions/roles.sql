-- Roles and the role hierarchy.
--
-- Replaces sql/init/002-init_roles.sql. Two changes beyond the keyword swap:
--
--   1. Role names are environment-prefixed. The old dbt_demo_* roles were
--      account-level and shared, but their comments claimed they were scoped to
--      dev_dbt_demo. With two targets on one account, sharing them would mean
--      both DCM projects reconciling grants on the same role and revoking each
--      other's work.
--
--   2. The access-role-to-functional-role grants lived in BOTH 002 and
--      004-grants.sql. They are declared once, here, next to the roles.
--
-- Account roles are used rather than database roles because dbt needs warehouse
-- USAGE, and Snowflake does not permit granting warehouse privileges to a
-- database role.

-- -----------------------------------------------------------------------
-- Access roles: what a principal may do to objects
-- -----------------------------------------------------------------------
DEFINE ROLE {{ env }}_dbt_demo_rw
    COMMENT = 'Access role for the {{ env }}_dbt_demo database with Read and Write permissions to all objects.';

DEFINE ROLE {{ env }}_dbt_demo_ro
    COMMENT = 'Access role for the {{ env }}_dbt_demo database with Read Only permissions to all objects.';

-- -----------------------------------------------------------------------
-- Functional roles: who a principal is
-- -----------------------------------------------------------------------
DEFINE ROLE {{ env }}_dbt_demo_data_engineer
    COMMENT = 'Functional role for {{ env }}_dbt_demo - business function alignment is generally for Data Engineers';

DEFINE ROLE {{ env }}_dbt_demo_analyst
    COMMENT = 'Functional role for {{ env }}_dbt_demo - business function alignment is generally for Data Analysts';

-- -----------------------------------------------------------------------
-- Access roles to functional roles
-- -----------------------------------------------------------------------
GRANT ROLE {{ env }}_dbt_demo_rw TO ROLE {{ env }}_dbt_demo_data_engineer;
GRANT ROLE {{ env }}_dbt_demo_ro TO ROLE {{ env }}_dbt_demo_analyst;

-- -----------------------------------------------------------------------
-- Functional roles to SYSADMIN, so SYSADMIN retains visibility
-- -----------------------------------------------------------------------
GRANT ROLE {{ env }}_dbt_demo_data_engineer TO ROLE sysadmin;
GRANT ROLE {{ env }}_dbt_demo_analyst TO ROLE sysadmin;

-- -----------------------------------------------------------------------
-- Functional roles to users
--
-- Was a hardcoded `GRANT ROLE dbt_demo_data_engineer TO USER tastyb`, which
-- broke on any account without that user. Now driven by admin_users in
-- manifest.yml, per target.
-- -----------------------------------------------------------------------
{% for user_name in admin_users %}
GRANT ROLE {{ env }}_dbt_demo_data_engineer TO USER {{ user_name }};
{% endfor %}
