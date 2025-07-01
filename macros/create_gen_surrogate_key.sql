{% macro create_gen_surrogate_key(database, schema) %}

{% set relation = api.Relation.create(database=database, schema=schema) %}

CREATE OR REPLACE FUNCTION {{ relation.database }}.{{ relation.schema }}.gen_surrogate_key(
    o OBJECT,
    default_null_value VARCHAR DEFAULT '_dbt_utils_surrogate_key_null_'
)
    RETURNS BINARY
AS
$$
    return MD5_BINARY(
             {{ relation.database }}.{{ relation.schema }}.concatenate_object_values(
                    o => o,
                    default_null_value => default_null_value)
    )
$$;

{% endmacro %}