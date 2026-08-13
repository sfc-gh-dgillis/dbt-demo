{#-
    One row per franchise_id, so d_franchise's surrogate key can be unique.

    raw.franchise lands 335 rows carrying only 325 distinct franchise_id, in two
    different shapes:

      1. Exact duplicate rows (ids 332-336). Every column matches, so collapsing
         them loses nothing.

      2. Multi-city franchisees (ids 36, 37, 49, 81, 123). Same person, e-mail,
         and phone number; only `city` differs. Brittany Williams (36) runs both
         Boston and Seattle.

    d_franchise derives franchise_key from franchise_id alone, and
    models/marts/schema.yml declares that column a primary_key with a unique
    test. The grain therefore has to be one row per franchise_id, which means
    class 2 cannot survive intact: the first city alphabetically wins and the
    other is dropped. That is a deliberate, lossy choice.

    If both cities ever need to be represented, the fix is to regrain
    franchise_key on (franchise_id, city) -- not to relax the filter here.

    `order by city` makes the survivor deterministic. Class 1 rows tie on every
    column, so which of them wins is irrelevant.
-#}

with source as (

    select * from {{ ref('stg_pos__franchise') }}

),

ranked as (

    select
        franchise_id,
        first_name,
        last_name,
        city,
        country,
        e_mail,
        phone_number,

        row_number() over (
            partition by franchise_id
            order by city
        ) as dedupe_rank

    from source

),

deduplicated as (

    select
        franchise_id,
        first_name,
        last_name,
        city,
        country,
        e_mail,
        phone_number

    from ranked
    where dedupe_rank = 1

)

select * from deduplicated
