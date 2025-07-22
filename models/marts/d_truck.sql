-- should this be named d_country_city or even split into d_country and d_city?
WITH pk_cte AS (SELECT spt.truck_id
                FROM {{ ref('stg_pos__truck') }} spt)

SELECT utilities.udf_generate_surrogate_key(o => OBJECT_CONSTRUCT_KEEP_NULL(pkc.*)) AS truck_key,
       spt.truck_id,
       spt.year,
       spt.make,
       spt.model,
       spt.truck_type,
       spt.is_electric,
       spt.truck_opening_date,
       spt.truck_brand_name
FROM {{ ref('stg_pos__truck') }} spt

         INNER JOIN pk_cte pkc
                    ON spt.country_id = pkc.country_id AND
                       spt.city_id = pkc.city_id
