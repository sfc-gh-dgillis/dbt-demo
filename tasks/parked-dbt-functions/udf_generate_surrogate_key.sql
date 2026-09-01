MD5_BINARY(
    {{ function('udf_concatenate_object_values') }}(
        o => o,
        default_null_value => default_null_value
    )
)
