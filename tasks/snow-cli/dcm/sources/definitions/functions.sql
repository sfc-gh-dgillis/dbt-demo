-- Surrogate key UDFs, in the utilities schema.
--
-- Parked from dbt function resources (tasks/parked-dbt-functions) while CoCo
-- Desktop cannot handle a functions/ folder in the project root. Move back once
-- that is fixed -- and note the ordering: build the dbt nodes BEFORE removing
-- these DEFINEs, because DCM drops an object when its definition disappears.
--
-- udf_concatenate_object_values is declared first for readability only. DCM
-- collects and sorts every DEFINE across all files, so declaration order is not
-- what makes this work; udf_generate_surrogate_key's body references the other
-- function, and Snowflake validates SQL UDF bodies at creation.
--
-- The two default null tokens differ and both are load bearing. They are
-- uppercased and hashed into every surrogate key in models/marts, so changing
-- either silently invalidates existing keys across all dimensions and facts.
-- udf_generate_surrogate_key passes its own token down explicitly, so the inner
-- default never applies.

DEFINE FUNCTION {{ base }}.utilities.udf_concatenate_object_values(
    o OBJECT,
    default_null_value VARCHAR DEFAULT '_SURROGATE_KEY_NULL_'
  )
  RETURNS STRING
  LANGUAGE PYTHON
  RUNTIME_VERSION = '3.12'
  HANDLER = 'concatenate_dict_values'
AS
$$
def concatenate_dict_values(input_dict, default_null_value="_SURROGATE_KEY_NULL_"):
    """
    Concatenate the values of a dict in key order, replacing empty values with a default, separated by '-'.
    All values are uppercased.
    Args:
        input_dict (dict): The dictionary whose values to concatenate.
        default_null_value (str): The value to use if a dict value is empty.
    Returns:
        str: Concatenated string of values in key order, separated by '-'
    """
    return '-'.join([
        str(input_dict[k]).upper() if input_dict[k] not in (None, '', []) else default_null_value.upper()
        for k in sorted(input_dict.keys())
    ])
$$;

DEFINE FUNCTION {{ base }}.utilities.udf_generate_surrogate_key(
    o OBJECT,
    default_null_value VARCHAR DEFAULT '_dbt_utils_surrogate_key_null_'
)
    RETURNS BINARY
AS
$$
    MD5_BINARY(
        {{ base }}.utilities.udf_concatenate_object_values(
            o => o,
            default_null_value => default_null_value)
    )
$$;
