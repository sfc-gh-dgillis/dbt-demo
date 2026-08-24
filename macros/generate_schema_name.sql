-- Overrides dbt's built-in schema resolution so that a model's `+schema:`
-- config is used verbatim instead of being suffixed onto the target schema.
--
-- dbt's default is `{{ target.schema }}_{{ custom_schema_name }}`, which would
-- turn `+schema: raw` into `modeled_raw`. We want the literal `raw`.
--
-- The exception is per-developer isolation. A developer sandbox resolves
-- DBT_CURRENT_SCHEMA to their own schema so concurrent work never collides.
-- Honoring a custom schema there would defeat that by sending every developer's
-- staging models to the same shared schema.
--
-- NOTE: this cannot be gated on `target.name`. The env.yml environment
-- (dbt_pdb / dev / prod) and the dbt target in profiles.yml are independent
-- axes: the environment is selected via ENVIRONMENT on EXECUTE DBT PROJECT while
-- the target is chosen with --target, so testing target.name would test the
-- wrong thing. The reliable signal is the resolved schema itself -- shared
-- environments set it to one of the names below, a per-developer schema is named
-- after its owner.
--
-- Note the current dbt_pdb sandbox does NOT rely on this branch: it isolates by
-- DATABASE and pins schema to `modeled`, so it takes the shared path below and
-- keeps the raw / curated / modeled layering inside its own database. The branch
-- still matters for any environment that isolates by schema instead.

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
