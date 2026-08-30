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
DEFINE ROLE {{ base }}_rw
    COMMENT = 'Access role for the {{ base }} database with Read and Write permissions to all objects.';

DEFINE ROLE {{ base }}_ro
    COMMENT = 'Access role for the {{ base }} database with Read Only permissions to all objects.';

-- -----------------------------------------------------------------------
-- Functional roles: who a principal is
-- -----------------------------------------------------------------------
DEFINE ROLE {{ base }}_data_engineer
    COMMENT = 'Functional role for {{ base }} - business function alignment is generally for Data Engineers';

DEFINE ROLE {{ base }}_analyst
    COMMENT = 'Functional role for {{ base }} - business function alignment is generally for Data Analysts';

-- -----------------------------------------------------------------------
-- Access roles to functional roles
-- -----------------------------------------------------------------------
GRANT ROLE {{ base }}_rw TO ROLE {{ base }}_data_engineer;
GRANT ROLE {{ base }}_ro TO ROLE {{ base }}_analyst;

-- -----------------------------------------------------------------------
-- Functional roles to SYSADMIN, so SYSADMIN retains visibility
-- -----------------------------------------------------------------------
GRANT ROLE {{ base }}_data_engineer TO ROLE sysadmin;
GRANT ROLE {{ base }}_analyst TO ROLE sysadmin;

-- -----------------------------------------------------------------------
-- Functional roles to users
-- -----------------------------------------------------------------------
{% for user_name in admin_users %}
GRANT ROLE {{ base }}_data_engineer TO USER {{ user_name }};
{% endfor %}
