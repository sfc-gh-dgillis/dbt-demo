-- Overrides dbt's built-in schema resolution so that a model's `+schema:`
-- config is used verbatim instead of being suffixed onto the target schema.
--
-- dbt's default is `{{ target.schema }}_{{ custom_schema_name }}`, which would
-- turn `+schema: raw` into `modeled_raw`. We want the literal `raw`.
--
-- The exception is per-developer isolation. The `dev_user` environment in
-- env.yml points DBT_CURRENT_SCHEMA at the developer's own schema so concurrent
-- work never collides. Honoring a custom schema there would defeat that by
-- sending every developer's staging models to the same shared schema.
--
-- NOTE: this cannot be gated on `target.name`. The env.yml environment
-- (dev / dev_user / prod) and the dbt target (dev / prod in profiles.yml) are
-- independent: `dev_user` is selected via ENVIRONMENT on EXECUTE DBT PROJECT
-- while the target stays `dev`, so `target.name` is never 'dev_user'. The
-- reliable signal is the resolved schema itself -- shared environments set it
-- to one of the names below, per-developer runs set it to a username.

{% macro generate_schema_name(custom_schema_name, node) -%}

    {%- set shared_schemas = ['modeled'] -%}

    {%- if custom_schema_name is none -%}
        {{ target.schema }}

    {#- Per-developer run: ignore custom schemas to preserve isolation. -#}
    {%- elif target.schema | lower not in shared_schemas -%}
        {{ target.schema }}

    {%- else -%}
        {{ custom_schema_name | trim }}
    {%- endif -%}

{%- endmacro %}
