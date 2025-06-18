

with source as (

    select * from {{ source('raw', 'country') }}

),

renamed as (

    select
        country_id,
        country,
        iso_currency,
        iso_country,
        city_id,
        city,
        city_population

    from source

)

select * from renamed

