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
