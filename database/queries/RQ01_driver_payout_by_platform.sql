/*
RQ01
How does the average driver payout differ between Uber-only,
Bolt-only and dual-platform drivers?
How are these differences associated with the platform
commission rates?
 */


/*
1. AVERAGE PAYOUT PER COMPLETED TRIP BY PLATFORM
*/

SELECT
    pa.affiliation_name AS platform_affiliation,

    ROUND(pa.commission_pct * 100, 0)
        AS commission_pct,

    COUNT(DISTINCT h.driver_id) AS drivers,

    COUNT(*) AS completed_trips,

    ROUND(AVG(f.total_fare_zar), 2)
        AS avg_total_fare_zar,

    ROUND(AVG(f.platform_commission_zar), 2)
        AS avg_commission_zar,

    ROUND(AVG(f.driver_payout_zar), 2)
        AS avg_payout_zar,

    ROUND(MEDIAN(f.driver_payout_zar), 2)
        AS median_payout_zar,

    ROUND(STDDEV(f.driver_payout_zar), 2)
        AS stddev_payout_zar,

    ROUND(
        AVG(f.driver_payout_zar)
        - MAX(AVG(f.driver_payout_zar)) OVER (),
        2
    ) AS diff_from_highest_zar,

    ROUND(
        100 *
        (
            AVG(f.driver_payout_zar)
            - MAX(AVG(f.driver_payout_zar)) OVER ()
        )
        / MAX(AVG(f.driver_payout_zar)) OVER (),
        2
    ) AS diff_from_highest_pct,

    RANK() OVER (
        ORDER BY AVG(f.driver_payout_zar) DESC
    ) AS payout_rank

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
    payout_rank;


/*
2. TOTAL PAYOUT PER DRIVER BY PLATFORM
*/

WITH driver_totals AS (
    SELECT
        d.driver_id,
        pa.affiliation_name,
        pa.commission_pct,
        COUNT(*) AS completed_trips,
        SUM(f.driver_payout_zar) AS total_payout
    FROM TRIP_HEADERS h
    JOIN TRIP_FARE_BREAKDOWN f
        ON h.trip_id = f.trip_id
    JOIN SA_DRIVERS d
        ON h.driver_id = d.driver_id
    JOIN PLATFORM_AFFILIATION pa
        ON d.affiliation_id = pa.affiliation_id
    WHERE h.trip_status = 'COMPLETED'
    GROUP BY
        d.driver_id,
        pa.affiliation_name,
        pa.commission_pct
),

overall_median AS (
    SELECT
        MEDIAN(total_payout) AS median_payout
    FROM driver_totals
)

SELECT
    dt.affiliation_name AS platform_affiliation,

    ROUND(dt.commission_pct * 100, 0)
        AS commission_pct,

    COUNT(*) AS drivers,

    ROUND(AVG(dt.completed_trips), 1)
        AS avg_trips_per_driver,

    ROUND(AVG(dt.total_payout), 2)
        AS avg_payout_per_driver_zar,

    ROUND(
        PERCENTILE_CONT(0.25)
            WITHIN GROUP (ORDER BY dt.total_payout),
        2
    ) AS q1_payout_per_driver_zar,

    ROUND(
        PERCENTILE_CONT(0.50)
            WITHIN GROUP (ORDER BY dt.total_payout),
        2
    ) AS median_payout_per_driver_zar,

    ROUND(
        PERCENTILE_CONT(0.75)
            WITHIN GROUP (ORDER BY dt.total_payout),
        2
    ) AS q3_payout_per_driver_zar,

    ROUND(MIN(dt.total_payout), 2)
        AS min_payout_per_driver_zar,

    ROUND(MAX(dt.total_payout), 2)
        AS max_payout_per_driver_zar,

    ROUND(
        100 *
        SUM(
            CASE
                WHEN dt.total_payout > om.median_payout
                THEN 1
                ELSE 0
            END
        ) / COUNT(*),
        1
    ) AS drivers_above_overall_median_pct

FROM driver_totals dt

CROSS JOIN overall_median om

GROUP BY
    dt.affiliation_name,
    dt.commission_pct

ORDER BY
    dt.commission_pct;


/*
3. ARE THE PAYOUT DIFFERENCES STATISTICALLY SIGNIFICANT?
*/

WITH trip_payouts AS (
    SELECT
        pa.affiliation_name AS platform,
        f.driver_payout_zar AS payout
    FROM TRIP_HEADERS h
    JOIN TRIP_FARE_BREAKDOWN f
        ON h.trip_id = f.trip_id
    JOIN SA_DRIVERS d
        ON h.driver_id = d.driver_id
    JOIN PLATFORM_AFFILIATION pa
        ON d.affiliation_id = pa.affiliation_id
    WHERE h.trip_status = 'COMPLETED'
),

platform_pairs AS (
    SELECT
        a.affiliation_name AS platform_a,
        b.affiliation_name AS platform_b
    FROM PLATFORM_AFFILIATION a
    JOIN PLATFORM_AFFILIATION b
        ON a.commission_pct < b.commission_pct
),

pair_stats AS (
    SELECT
        pp.platform_a,
        pp.platform_b,

        AVG(CASE WHEN tp.platform = pp.platform_a
                 THEN tp.payout END) AS avg_a,
        AVG(CASE WHEN tp.platform = pp.platform_b
                 THEN tp.payout END) AS avg_b,

        VARIANCE(CASE WHEN tp.platform = pp.platform_a
                      THEN tp.payout END) AS var_a,
        VARIANCE(CASE WHEN tp.platform = pp.platform_b
                      THEN tp.payout END) AS var_b,

        COUNT(CASE WHEN tp.platform = pp.platform_a
                   THEN 1 END) AS n_a,
        COUNT(CASE WHEN tp.platform = pp.platform_b
                   THEN 1 END) AS n_b

    FROM platform_pairs pp

    JOIN trip_payouts tp
        ON tp.platform IN (pp.platform_a, pp.platform_b)

    GROUP BY
        pp.platform_a,
        pp.platform_b
),

welch AS (
    SELECT
        platform_a,
        platform_b,
        avg_a,
        avg_b,
        avg_a - avg_b AS diff,
        SQRT(var_a / n_a + var_b / n_b) AS std_error,
        POWER(var_a / n_a + var_b / n_b, 2)
        / (
            POWER(var_a / n_a, 2) / (n_a - 1)
            + POWER(var_b / n_b, 2) / (n_b - 1)
          ) AS degrees_of_freedom
    FROM pair_stats
)

SELECT
    platform_a AS lower_commission_platform,
    platform_b AS higher_commission_platform,

    ROUND(avg_a, 2) AS avg_payout_a_zar,
    ROUND(avg_b, 2) AS avg_payout_b_zar,

    ROUND(diff, 2) AS payout_difference_zar,

    ROUND(diff - 1.96 * std_error, 2)
        AS ci95_lower_zar,

    ROUND(diff + 1.96 * std_error, 2)
        AS ci95_upper_zar,

    ROUND(diff / std_error, 3) AS t_statistic,

    ROUND(degrees_of_freedom, 0) AS degrees_of_freedom,

    CASE
        WHEN ABS(diff / std_error) > 1.96
        THEN 'Yes'
        ELSE 'No'
    END AS significant_at_5pct

FROM welch

ORDER BY
    payout_difference_zar DESC;


/*
4. HOW MUCH OF EACH EXTRA RAND OF FARE REACHES THE DRIVER
*/

SELECT
    pa.affiliation_name AS platform_affiliation,

    ROUND(pa.commission_pct * 100, 0)
        AS commission_pct,

    ROUND((1 - pa.commission_pct) * 100, 2)
        AS expected_rand_per_r100_fare,

    ROUND(
        100 * REGR_SLOPE(
            f.driver_payout_zar,
            f.total_fare_zar - f.tip_zar - f.tolls_zar
        ),
        2
    ) AS observed_rand_per_r100_fare,

    ROUND(
        REGR_INTERCEPT(
            f.driver_payout_zar,
            f.total_fare_zar - f.tip_zar - f.tolls_zar
        ),
        2
    ) AS intercept_zar,

    ROUND(
        REGR_R2(
            f.driver_payout_zar,
            f.total_fare_zar - f.tip_zar - f.tolls_zar
        ),
        4
    ) AS r_squared

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
5. HOW MUCH OF THE PAYOUT GAP IS CAUSED BY COMMISSION?
*/

WITH platform_avg AS (
    SELECT
        pa.affiliation_name,
        pa.commission_pct,
        COUNT(*) AS completed_trips,
        AVG(f.total_fare_zar - f.tip_zar - f.tolls_zar)
            AS commissionable_fare,
        AVG(f.tip_zar + f.tolls_zar) AS tips_tolls,
        AVG(f.driver_payout_zar) AS payout
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
),

baseline AS (
    SELECT *
    FROM platform_avg
    WHERE commission_pct = (
        SELECT MIN(commission_pct)
        FROM platform_avg
    )
)

SELECT
    p.affiliation_name AS platform_affiliation,

    ROUND(p.commission_pct * 100, 0)
        AS commission_pct,

    p.completed_trips,

    ROUND(p.commissionable_fare, 2)
        AS avg_commissionable_fare_zar,

    ROUND(p.tips_tolls, 2)
        AS avg_tips_tolls_zar,

    ROUND(p.payout, 2) AS avg_payout_zar,

    ROUND(p.payout - b.payout, 2)
        AS gap_vs_lowest_commission_zar,

    ROUND(
        p.commissionable_fare
        * (b.commission_pct - p.commission_pct),
        2
    ) AS commission_rate_effect_zar,

    ROUND(
        (p.commissionable_fare - b.commissionable_fare)
        * (1 - b.commission_pct)
        + (p.tips_tolls - b.tips_tolls),
        2
    ) AS trip_value_effect_zar,

    ROUND(
        100 *
        p.commissionable_fare
        * (b.commission_pct - p.commission_pct)
        / NULLIF(p.payout - b.payout, 0),
        1
    ) AS gap_from_commission_pct

FROM platform_avg p

CROSS JOIN baseline b

ORDER BY
    p.commission_pct;


/*
6. THE SAME TRIPS PRICED AT EVERY COMMISSION RATE
*/

SELECT
    pa_driver.affiliation_name AS driver_platform,

    ROUND(pa_driver.commission_pct * 100, 0)
        AS actual_commission_pct,

    COUNT(DISTINCT h.trip_id) AS completed_trips,

    ROUND(
        AVG(
            CASE
                WHEN pa_rate.affiliation_id = pa_driver.affiliation_id
                THEN f.driver_payout_zar
            END
        ),
        2
    ) AS actual_avg_payout_zar,

    ROUND(
        AVG(
            CASE
                WHEN pa_rate.affiliation_name = 'Bolt'
                THEN (f.total_fare_zar - f.tip_zar - f.tolls_zar)
                     * (1 - pa_rate.commission_pct)
                     + f.tip_zar + f.tolls_zar
            END
        ),
        2
    ) AS payout_at_bolt_rate_zar,

    ROUND(
        AVG(
            CASE
                WHEN pa_rate.affiliation_name = 'Dual-Platform (Both)'
                THEN (f.total_fare_zar - f.tip_zar - f.tolls_zar)
                     * (1 - pa_rate.commission_pct)
                     + f.tip_zar + f.tolls_zar
            END
        ),
        2
    ) AS payout_at_dual_rate_zar,

    ROUND(
        AVG(
            CASE
                WHEN pa_rate.affiliation_name = 'Uber'
                THEN (f.total_fare_zar - f.tip_zar - f.tolls_zar)
                     * (1 - pa_rate.commission_pct)
                     + f.tip_zar + f.tolls_zar
            END
        ),
        2
    ) AS payout_at_uber_rate_zar,

    ROUND(
        AVG(
            CASE
                WHEN pa_rate.affiliation_name = 'Bolt'
                THEN (f.total_fare_zar - f.tip_zar - f.tolls_zar)
                     * (1 - pa_rate.commission_pct)
            END
        )
        - AVG(
            CASE
                WHEN pa_rate.affiliation_name = 'Uber'
                THEN (f.total_fare_zar - f.tip_zar - f.tolls_zar)
                     * (1 - pa_rate.commission_pct)
            END
        ),
        2
    ) AS bolt_vs_uber_rate_gap_zar

FROM TRIP_HEADERS h

JOIN TRIP_FARE_BREAKDOWN f
    ON h.trip_id = f.trip_id

JOIN SA_DRIVERS d
    ON h.driver_id = d.driver_id

JOIN PLATFORM_AFFILIATION pa_driver
    ON d.affiliation_id = pa_driver.affiliation_id

CROSS JOIN PLATFORM_AFFILIATION pa_rate

WHERE h.trip_status = 'COMPLETED'

GROUP BY
    pa_driver.affiliation_name,
    pa_driver.commission_pct

ORDER BY
    pa_driver.commission_pct;


/*
7. LIKE-FOR-LIKE COMPARISON WITHIN EACH CITY
*/

SELECT
    city_name,

    ROUND(bolt_avg, 2) AS bolt_avg_payout_zar,
    ROUND(dual_avg, 2) AS dual_avg_payout_zar,
    ROUND(uber_avg, 2) AS uber_avg_payout_zar,

    ROUND(bolt_avg - uber_avg, 2)
        AS bolt_vs_uber_gap_zar,

    ROUND(100 * (bolt_avg - uber_avg) / uber_avg, 2)
        AS bolt_vs_uber_gap_pct,

    CASE
        WHEN bolt_avg > dual_avg
         AND dual_avg > uber_avg
        THEN 'Yes'
        ELSE 'No'
    END AS follows_commission_order,

    SUM(
        CASE
            WHEN bolt_avg > dual_avg
             AND dual_avg > uber_avg
            THEN 1
            ELSE 0
        END
    ) OVER () AS cities_following_order

FROM (
    SELECT
        c.city_name,
        pa.affiliation_name,
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
)

PIVOT (
    AVG(driver_payout_zar)
    FOR affiliation_name IN (
        'Bolt' AS bolt_avg,
        'Dual-Platform (Both)' AS dual_avg,
        'Uber' AS uber_avg
    )
)

ORDER BY
    bolt_vs_uber_gap_zar DESC;


/*
8. PAYOUT ADJUSTED FOR CITY AND RIDE CATEGORY MIX
*/

WITH cell_avg AS (
    SELECT
        pa.affiliation_name,
        pa.commission_pct,
        c.city_name,
        h.ride_category,
        AVG(f.driver_payout_zar) AS avg_payout
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
    GROUP BY
        pa.affiliation_name,
        pa.commission_pct,
        c.city_name,
        h.ride_category
    HAVING COUNT(*) >= 30
),

trip_mix AS (
    SELECT
        c.city_name,
        h.ride_category,
        RATIO_TO_REPORT(COUNT(*)) OVER () AS mix_weight
    FROM TRIP_HEADERS h
    JOIN PRICING_SURGE_ZONES z
        ON h.zone_id = z.zone_id
    JOIN CITIES c
        ON z.city_id = c.city_id
    WHERE h.trip_status = 'COMPLETED'
    GROUP BY
        c.city_name,
        h.ride_category
),

raw_avg AS (
    SELECT
        pa.affiliation_name,
        AVG(f.driver_payout_zar) AS avg_payout
    FROM TRIP_HEADERS h
    JOIN TRIP_FARE_BREAKDOWN f
        ON h.trip_id = f.trip_id
    JOIN SA_DRIVERS d
        ON h.driver_id = d.driver_id
    JOIN PLATFORM_AFFILIATION pa
        ON d.affiliation_id = pa.affiliation_id
    WHERE h.trip_status = 'COMPLETED'
    GROUP BY
        pa.affiliation_name
),

standardised AS (
    SELECT
        ca.affiliation_name,
        ca.commission_pct,
        SUM(tm.mix_weight * ca.avg_payout) AS std_payout,
        SUM(tm.mix_weight) AS mix_coverage
    FROM cell_avg ca
    JOIN trip_mix tm
        ON ca.city_name = tm.city_name
       AND ca.ride_category = tm.ride_category
    GROUP BY
        ca.affiliation_name,
        ca.commission_pct
)

SELECT
    s.affiliation_name AS platform_affiliation,

    ROUND(s.commission_pct * 100, 0)
        AS commission_pct,

    ROUND(r.avg_payout, 2) AS raw_avg_payout_zar,

    ROUND(s.std_payout, 2) AS mix_adjusted_payout_zar,

    ROUND(
        r.avg_payout - MAX(r.avg_payout) OVER (),
        2
    ) AS raw_gap_from_highest_zar,

    ROUND(
        s.std_payout - MAX(s.std_payout) OVER (),
        2
    ) AS adjusted_gap_from_highest_zar,

    ROUND(s.mix_coverage, 3) AS mix_coverage

FROM standardised s

JOIN raw_avg r
    ON s.affiliation_name = r.affiliation_name

ORDER BY
    s.commission_pct;
