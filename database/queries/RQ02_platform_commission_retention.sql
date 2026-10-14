/*
RQ02
What proportion of the total fare value does each platform
retain as commission?
How does this vary by platform, city and ride category?
 */


/*
1. COMMISSION RETAINED BY EACH PLATFORM
*/

SELECT
    CASE
        WHEN GROUPING(pa.affiliation_name) = 1
        THEN 'All platforms'
        ELSE pa.affiliation_name
    END AS platform_affiliation,

    CASE
        WHEN GROUPING(pa.affiliation_name) = 0
        THEN ROUND(MAX(pa.commission_pct) * 100, 0)
    END AS nominal_commission_pct,

    COUNT(*) AS completed_trips,

    ROUND(SUM(f.total_fare_zar), 2)
        AS total_fare_zar,

    ROUND(
        SUM(
            f.total_fare_zar
            - f.tip_zar
            - f.tolls_zar
        ),
        2
    ) AS commissionable_fare_zar,

    ROUND(SUM(f.platform_commission_zar), 2)
        AS commission_revenue_zar,

    ROUND(AVG(f.platform_commission_zar), 2)
        AS avg_commission_per_trip_zar,

    ROUND(
        100 * SUM(f.platform_commission_zar)
        / SUM(f.total_fare_zar),
        2
    ) AS retained_of_total_fare_pct,

    ROUND(
        100 * SUM(f.platform_commission_zar)
        / SUM(
            f.total_fare_zar
            - f.tip_zar
            - f.tolls_zar
        ),
        2
    ) AS retained_of_commissionable_pct,

    CASE
        WHEN GROUPING(pa.affiliation_name) = 0
        THEN ROUND(
            MAX(pa.commission_pct) * 100
            - 100 * SUM(f.platform_commission_zar)
              / SUM(f.total_fare_zar),
            2
        )
    END AS below_nominal_pct_points,

    ROUND(
        100 * COUNT(*)
        / SUM(COUNT(*)) OVER (
            PARTITION BY GROUPING(pa.affiliation_name)
        ),
        2
    ) AS share_of_trips_pct,

    ROUND(
        100 * SUM(f.platform_commission_zar)
        / SUM(SUM(f.platform_commission_zar)) OVER (
            PARTITION BY GROUPING(pa.affiliation_name)
        ),
        2
    ) AS share_of_commission_revenue_pct

FROM TRIP_HEADERS h

JOIN TRIP_FARE_BREAKDOWN f
    ON h.trip_id = f.trip_id

JOIN SA_DRIVERS d
    ON h.driver_id = d.driver_id

JOIN PLATFORM_AFFILIATION pa
    ON d.affiliation_id = pa.affiliation_id

WHERE h.trip_status = 'COMPLETED'

GROUP BY ROLLUP (pa.affiliation_name)

ORDER BY
    GROUPING(pa.affiliation_name),
    MAX(pa.commission_pct);


/*
2. COMMISSION RETAINED BY CITY
*/

WITH city_platform AS (
    SELECT
        c.city_name,
        p.province_name,
        pa.affiliation_name,
        pa.commission_pct,
        COUNT(*) AS completed_trips,
        SUM(f.total_fare_zar) AS total_fare,
        SUM(f.tip_zar + f.tolls_zar) AS tips_tolls,
        SUM(f.platform_commission_zar) AS commission
    FROM TRIP_HEADERS h
    JOIN TRIP_FARE_BREAKDOWN f
        ON h.trip_id = f.trip_id
    JOIN SA_DRIVERS d
        ON h.driver_id = d.driver_id
    JOIN PLATFORM_AFFILIATION pa
        ON d.affiliation_id = pa.affiliation_id
    JOIN PRICING_SURGE_ZONES z
        ON h.zone_id = z.zone_id
    JOIN CITIES c
        ON z.city_id = c.city_id
    JOIN PROVINCES p
        ON c.province_id = p.province_id
    WHERE h.trip_status = 'COMPLETED'
    GROUP BY
        c.city_name,
        p.province_name,
        pa.affiliation_name,
        pa.commission_pct
)

SELECT
    city_name,
    province_name,

    SUM(completed_trips) AS completed_trips,

    ROUND(SUM(commission), 2)
        AS commission_revenue_zar,

    ROUND(SUM(commission) / SUM(completed_trips), 2)
        AS avg_commission_per_trip_zar,

    ROUND(
        100 * RATIO_TO_REPORT(SUM(completed_trips)) OVER (),
        2
    ) AS share_of_trips_pct,

    ROUND(
        100 * RATIO_TO_REPORT(SUM(commission)) OVER (),
        2
    ) AS share_of_commission_revenue_pct,

    ROUND(
        100 *
        SUM(CASE WHEN affiliation_name = 'Bolt'
                 THEN commission END)
        / SUM(CASE WHEN affiliation_name = 'Bolt'
                   THEN total_fare END),
        2
    ) AS bolt_retained_pct,

    ROUND(
        100 *
        SUM(CASE WHEN affiliation_name = 'Dual-Platform (Both)'
                 THEN commission END)
        / SUM(CASE WHEN affiliation_name = 'Dual-Platform (Both)'
                   THEN total_fare END),
        2
    ) AS dual_retained_pct,

    ROUND(
        100 *
        SUM(CASE WHEN affiliation_name = 'Uber'
                 THEN commission END)
        / SUM(CASE WHEN affiliation_name = 'Uber'
                   THEN total_fare END),
        2
    ) AS uber_retained_pct,

    ROUND(
        100 * SUM(commission) / SUM(total_fare),
        2
    ) AS all_platforms_retained_pct,

    ROUND(
        100 * SUM(commission_pct * total_fare)
        / SUM(total_fare),
        2
    ) AS fare_weighted_nominal_pct,

    ROUND(
        100 *
        SUM(CASE WHEN affiliation_name = 'Uber'
                 THEN completed_trips END)
        / SUM(completed_trips),
        1
    ) AS uber_share_of_trips_pct,

    ROUND(
        100 * SUM(tips_tolls) / SUM(total_fare),
        2
    ) AS tips_tolls_share_of_fare_pct,

    RANK() OVER (
        ORDER BY SUM(commission) / SUM(total_fare) DESC
    ) AS retained_pct_rank

FROM city_platform

GROUP BY
    city_name,
    province_name

ORDER BY
    retained_pct_rank;


/*
3. COMMISSION RETAINED BY RIDE CATEGORY AND PLATFORM
*/

SELECT
    CASE
        WHEN GROUPING(pa.affiliation_name) = 1
        THEN 'All platforms'
        ELSE pa.affiliation_name
    END AS platform_affiliation,

    CASE
        WHEN GROUPING(h.ride_category) = 1
        THEN 'All categories'
        ELSE h.ride_category
    END AS ride_category,

    COUNT(*) AS completed_trips,

    ROUND(SUM(f.total_fare_zar), 2)
        AS total_fare_zar,

    ROUND(SUM(f.platform_commission_zar), 2)
        AS commission_revenue_zar,

    ROUND(AVG(f.platform_commission_zar), 2)
        AS avg_commission_per_trip_zar,

    ROUND(
        100 * SUM(f.platform_commission_zar)
        / SUM(f.total_fare_zar),
        2
    ) AS retained_of_total_fare_pct

FROM TRIP_HEADERS h

JOIN TRIP_FARE_BREAKDOWN f
    ON h.trip_id = f.trip_id

JOIN SA_DRIVERS d
    ON h.driver_id = d.driver_id

JOIN PLATFORM_AFFILIATION pa
    ON d.affiliation_id = pa.affiliation_id

WHERE h.trip_status = 'COMPLETED'

GROUP BY CUBE (
    pa.affiliation_name,
    h.ride_category
)

ORDER BY
    GROUPING(pa.affiliation_name),
    pa.affiliation_name,
    GROUPING(h.ride_category),
    h.ride_category;


/*
4. WHICH FACTOR CAUSES THE MOST VARIATION
*/

WITH member_rates AS (
    SELECT
        CASE
            WHEN GROUPING(pa.affiliation_name) = 0
            THEN 'Platform'
            WHEN GROUPING(c.city_name) = 0
            THEN 'City'
            ELSE 'Ride category'
        END AS dimension,

        COALESCE(
            pa.affiliation_name,
            c.city_name,
            h.ride_category
        ) AS member,

        100 * SUM(f.platform_commission_zar)
        / SUM(f.total_fare_zar) AS retained_pct

    FROM TRIP_HEADERS h
    JOIN TRIP_FARE_BREAKDOWN f
        ON h.trip_id = f.trip_id
    JOIN SA_DRIVERS d
        ON h.driver_id = d.driver_id
    JOIN PLATFORM_AFFILIATION pa
        ON d.affiliation_id = pa.affiliation_id
    JOIN PRICING_SURGE_ZONES z
        ON h.zone_id = z.zone_id
    JOIN CITIES c
        ON z.city_id = c.city_id
    WHERE h.trip_status = 'COMPLETED'
    GROUP BY GROUPING SETS (
        (pa.affiliation_name),
        (c.city_name),
        (h.ride_category)
    )
)

SELECT
    dimension,

    COUNT(*) AS members,

    MIN(member) KEEP (
        DENSE_RANK FIRST ORDER BY retained_pct
    ) AS lowest_member,

    ROUND(MIN(retained_pct), 2)
        AS lowest_retained_pct,

    MAX(member) KEEP (
        DENSE_RANK LAST ORDER BY retained_pct
    ) AS highest_member,

    ROUND(MAX(retained_pct), 2)
        AS highest_retained_pct,

    ROUND(MAX(retained_pct) - MIN(retained_pct), 2)
        AS range_pct_points,

    ROUND(STDDEV(retained_pct), 3)
        AS stddev_pct_points

FROM member_rates

GROUP BY
    dimension

ORDER BY
    range_pct_points DESC;


/*
5. WHY PLATFORMS RETAIN LESS THAN THEIR NOMINAL RATE
*/

SELECT
    pa.affiliation_name AS platform_affiliation,

    ROUND(pa.commission_pct * 100, 0)
        AS nominal_commission_pct,

    ROUND(
        100 *
        SUM(CASE WHEN f.tip_zar > 0 THEN 1 ELSE 0 END)
        / COUNT(*),
        2
    ) AS trips_with_tip_pct,

    ROUND(
        100 *
        SUM(CASE WHEN f.tolls_zar > 0 THEN 1 ELSE 0 END)
        / COUNT(*),
        2
    ) AS trips_with_toll_pct,

    ROUND(SUM(f.tip_zar), 2) AS total_tips_zar,

    ROUND(SUM(f.tolls_zar), 2) AS total_tolls_zar,

    ROUND(
        100 * SUM(f.tip_zar + f.tolls_zar)
        / SUM(f.total_fare_zar),
        2
    ) AS uncommissioned_share_pct,

    ROUND(
        SUM(f.tip_zar + f.tolls_zar) * pa.commission_pct,
        2
    ) AS commission_not_charged_zar,

    ROUND(
        100 * pa.commission_pct
        * (
            1
            - SUM(f.tip_zar + f.tolls_zar)
              / SUM(f.total_fare_zar)
          ),
        2
    ) AS predicted_retained_pct,

    ROUND(
        100 * SUM(f.platform_commission_zar)
        / SUM(f.total_fare_zar),
        2
    ) AS actual_retained_pct

FROM TRIP_HEADERS h

JOIN TRIP_FARE_BREAKDOWN f
    ON h.trip_id = f.trip_id

JOIN SA_DRIVERS d
    ON h.driver_id = d.driver_id

JOIN PLATFORM_AFFILIATION pa
    ON d.affiliation_id = pa.affiliation_id

WHERE h.trip_status = 'COMPLETED'

GROUP BY
    pa.affiliation_name,
    pa.commission_pct

ORDER BY
    pa.commission_pct;


/*
6. TIPS, TOLLS AND RETENTION PER CITY WITHIN EACH PLATFORM
*/

WITH platform_city AS (
    SELECT
        pa.affiliation_name,
        pa.commission_pct,
        c.city_name,
        p.province_name,
        COUNT(*) AS completed_trips,
        SUM(CASE WHEN f.tolls_zar > 0 THEN 1 ELSE 0 END)
            AS toll_trips,
        SUM(f.total_fare_zar) AS total_fare,
        SUM(f.tip_zar) AS tips,
        SUM(f.tolls_zar) AS tolls,
        SUM(f.platform_commission_zar) AS commission
    FROM TRIP_HEADERS h
    JOIN TRIP_FARE_BREAKDOWN f
        ON h.trip_id = f.trip_id
    JOIN SA_DRIVERS d
        ON h.driver_id = d.driver_id
    JOIN PLATFORM_AFFILIATION pa
        ON d.affiliation_id = pa.affiliation_id
    JOIN PRICING_SURGE_ZONES z
        ON h.zone_id = z.zone_id
    JOIN CITIES c
        ON z.city_id = c.city_id
    JOIN PROVINCES p
        ON c.province_id = p.province_id
    WHERE h.trip_status = 'COMPLETED'
    GROUP BY
        pa.affiliation_name,
        pa.commission_pct,
        c.city_name,
        p.province_name
)

SELECT
    affiliation_name AS platform_affiliation,
    city_name,
    province_name,

    completed_trips,

    ROUND(100 * toll_trips / completed_trips, 1)
        AS trips_with_toll_pct,

    ROUND(100 * tips / total_fare, 2)
        AS tip_share_of_fare_pct,

    ROUND(100 * tolls / total_fare, 2)
        AS toll_share_of_fare_pct,

    ROUND(100 * commission / total_fare, 2)
        AS retained_pct,

    ROUND(
        100 * commission_pct
        - 100 * commission / total_fare,
        2
    ) AS below_nominal_pct_points,

    RANK() OVER (
        PARTITION BY affiliation_name
        ORDER BY commission / total_fare DESC
    ) AS rank_within_platform,

    ROUND(
        CORR(
            (tips + tolls) / total_fare,
            commission / total_fare
        ) OVER (PARTITION BY affiliation_name),
        4
    ) AS corr_tips_tolls_vs_retained

FROM platform_city

ORDER BY
    commission_pct,
    rank_within_platform;
