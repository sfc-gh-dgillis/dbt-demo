{% macro create_concatenate_object_values(database, schema) %}

{% set relation = api.Relation.create(database=database, schema=schema) %}

CREATE OR REPLACE FUNCTION {{ relation.database }}.{{ relation.schema }}.concatenate_object_values(
    o OBJECT,
    default_null_value VARCHAR DEFAULT '_dbt_utils_surrogate_key_null_'
  )
  RETURNS STRING
  LANGUAGE PYTHON
  RUNTIME_VERSION = '3.12'
  HANDLER = 'concatenate_dict_values'
AS
$$
def concatenate_dict_values(input_dict, default_null_value="_dbt_utils_surrogate_key_null_"):
    """
    Concatenate the values of a dict in key order, replacing empty values with a default, separated by '-'.
    Args:
        input_dict (dict): The dictionary whose values to concatenate.
        default_null_value (str): The value to use if a dict value is empty.
    Returns:
        str: Concatenated string of values in key order, separated by '-'
    """
    return '-'.join([
        str(input_dict[k]) if input_dict[k] not in (None, '', []) else default_null_value
        for k in sorted(input_dict.keys())
    ])
$$;

{% endmacro %}