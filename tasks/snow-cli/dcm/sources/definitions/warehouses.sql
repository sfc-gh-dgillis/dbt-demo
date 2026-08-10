-- Warehouses.
--
-- Replaces sql/init/001-create_warehouses.sql, which used
-- CREATE OR REPLACE WAREHOUSE. That was destructive and not idempotent: every
-- `task demo-up` dropped and recreated all six warehouses, silently discarding
-- the USAGE grants applied later in the same run. DEFINE converges instead:
-- an existing warehouse of the right size is left untouched.
--
-- AUTO_SUSPEND and AUTO_RESUME are now explicit rather than relying on the
-- account defaults the old script inherited.
--
-- INITIALLY_SUSPENDED only applies at creation time and cannot be altered
-- afterwards, so it never shows up as drift.

{% for wh in warehouses %}
DEFINE WAREHOUSE {{ env }}_dbt_demo_{{ wh.suffix }}_wh
WITH
    WAREHOUSE_SIZE = '{{ wh.size }}'
    AUTO_SUSPEND = 600
    AUTO_RESUME = TRUE
    INITIALLY_SUSPENDED = TRUE
    COMMENT = 'dbt {{ env_label }} - {{ wh.size }} warehouse';
{% endfor %}
