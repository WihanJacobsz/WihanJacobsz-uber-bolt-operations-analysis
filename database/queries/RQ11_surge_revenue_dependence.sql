/* ============================================================
   RQ11 - Surge Revenue Dependence

   To what extent do drivers depend on surge-priced periods
   for their total earnings?

   What percentage of total driver payout is earned during
   surge-priced periods, and how does this vary across
   platforms, cities and ride categories?
   ============================================================ */


/* ============================================================
   1. OVERALL SURGE DEPENDENCE
   ============================================================ */

SELECT
    COUNT(*) AS total_completed_trips,

    SUM(
        CASE
            WHEN f.surge_multiplier > 1
            THEN 1
            ELSE 0
        END
    ) AS surge_trips_count,

    ROUND(
        100 *
        SUM(
            CASE
                WHEN f.surge_multiplier > 1
                THEN 1
                ELSE 0
            END
        ) / COUNT(*),
        2
    ) AS surge_trip_frequency_pct,

    ROUND(SUM(f.driver_payout_zar), 2)
        AS total_driver_payout_zar,

    ROUND(
        SUM(
            CASE
                WHEN f.surge_multiplier > 1
                THEN f.driver_payout_zar
                ELSE 0
            END
        ),
        2
    ) AS surge_driver_payout_zar,

    ROUND(
        100 *
        SUM(
            CASE
                WHEN f.surge_multiplier > 1
                THEN f.driver_payout_zar
                ELSE 0
            END
        )
        / NULLIF(SUM(f.driver_payout_zar), 0),
        2
    ) AS surge_payout_dependence_pct,

    ROUND(
        AVG(
            CASE
                WHEN f.surge_multiplier > 1
                THEN f.driver_payout_zar
            END
        ),
        2
    ) AS avg_payout_surge_trip_zar,

    ROUND(
        AVG(
            CASE
                WHEN f.surge_multiplier = 1
                THEN f.driver_payout_zar
            END
        ),
        2
    ) AS avg_payout_non_surge_trip_zar

FROM TRIP_HEADERS h

JOIN TRIP_FARE_BREAKDOWN f
    ON h.trip_id = f.trip_id

WHERE h.trip_status = 'COMPLETED';


/* ============================================================
   2. SURGE DEPENDENCE BY PLATFORM, CITY AND RIDE CATEGORY
   ============================================================ */

WITH completed_trips AS (
    SELECT
        pa.affiliation_name AS platform_affiliation,
        c.city_name,
        h.ride_category,
        f.surge_multiplier,
        f.driver_payout_zar

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
),

dimension_summary AS (

    SELECT
        'Platform' AS dimension_type,
        platform_affiliation AS dimension_value,
        COUNT(*) AS completed_trips,
        SUM(
            CASE
                WHEN surge_multiplier > 1
                THEN 1
                ELSE 0
            END
        ) AS surge_trips,
        SUM(driver_payout_zar) AS total_payout,
        SUM(
            CASE
                WHEN surge_multiplier > 1
                THEN driver_payout_zar
                ELSE 0
            END
        ) AS surge_payout

    FROM completed_trips
    GROUP BY platform_affiliation

    UNION ALL

    SELECT
        'City',
        city_name,
        COUNT(*),
        SUM(
            CASE
                WHEN surge_multiplier > 1
                THEN 1
                ELSE 0
            END
        ),
        SUM(driver_payout_zar),
        SUM(
            CASE
                WHEN surge_multiplier > 1
                THEN driver_payout_zar
                ELSE 0
            END
        )

    FROM completed_trips
    GROUP BY city_name

    UNION ALL

    SELECT
        'Ride Category',
        ride_category,
        COUNT(*),
        SUM(
            CASE
                WHEN surge_multiplier > 1
                THEN 1
                ELSE 0
            END
        ),
        SUM(driver_payout_zar),
        SUM(
            CASE
                WHEN surge_multiplier > 1
                THEN driver_payout_zar
                ELSE 0
            END
        )

    FROM completed_trips
    GROUP BY ride_category
),

calculated AS (
    SELECT
        dimension_type,
        dimension_value,
        completed_trips,
        surge_trips,

        ROUND(
            100 * surge_trips / completed_trips,
            2
        ) AS surge_trip_frequency_pct,

        ROUND(total_payout, 2)
            AS total_driver_payout_zar,

        ROUND(surge_payout, 2)
            AS surge_driver_payout_zar,

        ROUND(
            100 * surge_payout / NULLIF(total_payout, 0),
            2
        ) AS surge_payout_dependence_pct

    FROM dimension_summary
)

SELECT
    dimension_type,
    dimension_value,
    completed_trips,
    surge_trips,
    surge_trip_frequency_pct,
    total_driver_payout_zar,
    surge_driver_payout_zar,
    surge_payout_dependence_pct,

    RANK() OVER (
        PARTITION BY dimension_type
        ORDER BY surge_payout_dependence_pct DESC
    ) AS dependence_rank

FROM calculated

ORDER BY
    dimension_type,
    dependence_rank,
    dimension_value;