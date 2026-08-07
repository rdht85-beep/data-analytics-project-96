WITH sessions_flagged AS (
    SELECT
        visitor_id,
        source,
        medium,
        campaign,
        visit_date,
        (medium NOT IN ('organic')) AS is_paid
    FROM sessions
),
visits_agg AS (
    SELECT
        visit_date::date AS visit_date,
        source   AS utm_source,
        medium   AS utm_medium,
        campaign AS utm_campaign,
        COUNT(DISTINCT visitor_id) AS visitors_count
    FROM sessions_flagged
    WHERE is_paid = TRUE
    GROUP BY visit_date::date, source, medium, campaign
),
ads_union AS (
    SELECT campaign_date, utm_source, utm_medium, utm_campaign, daily_spent
    FROM vk_ads
    UNION ALL
    SELECT campaign_date, utm_source, utm_medium, utm_campaign, daily_spent
    FROM ya_ads
),
spend_agg AS (
    SELECT
        campaign_date::date AS visit_date,
        utm_source,
        utm_medium,
        utm_campaign,
        SUM(daily_spent) AS total_cost
    FROM ads_union
    GROUP BY campaign_date::date, utm_source, utm_medium, utm_campaign
),
last_paid_for_lead_ranked AS (
    SELECT
        s.visitor_id,
        s.visit_date,
        s.source   AS utm_source,
        s.medium   AS utm_medium,
        s.campaign AS utm_campaign,
        l.lead_id,
        l.amount,
        l.closing_reason,
        l.status_id,
        ROW_NUMBER() OVER (
            PARTITION BY l.lead_id
            ORDER BY s.visit_date DESC
        ) AS rn
    FROM leads l
    JOIN sessions_flagged s
        ON s.visitor_id = l.visitor_id
       AND s.is_paid
       AND s.visit_date <= l.created_at
),
last_paid_for_lead AS (
    SELECT
        visitor_id, visit_date, utm_source, utm_medium, utm_campaign,
        lead_id, amount, closing_reason, status_id
    FROM last_paid_for_lead_ranked
    WHERE rn = 1
),
leads_agg AS (
    SELECT
        visit_date::date AS visit_date,
        utm_source,
        utm_medium,
        utm_campaign,
        COUNT(DISTINCT lead_id) AS leads_count,
        COUNT(DISTINCT lead_id) FILTER (
            WHERE status_id = 142
        ) AS purchases_count,
        SUM(amount) FILTER (
            WHERE status_id = 142
        ) AS revenue
    FROM last_paid_for_lead
    GROUP BY visit_date::date, utm_source, utm_medium, utm_campaign
),
all_keys AS (
    SELECT visit_date, utm_source, utm_medium, utm_campaign FROM visits_agg
    UNION
    SELECT visit_date, utm_source, utm_medium, utm_campaign FROM spend_agg
    UNION
    SELECT visit_date, utm_source, utm_medium, utm_campaign FROM leads_agg
)
SELECT
    k.visit_date,
    v.visitors_count,
    k.utm_source,
    k.utm_medium,
    k.utm_campaign,
    sp.total_cost,
    l.leads_count,
    l.purchases_count,
    l.revenue
FROM all_keys k
LEFT JOIN visits_agg v
    ON v.visit_date = k.visit_date
   AND v.utm_source IS NOT DISTINCT FROM k.utm_source
   AND v.utm_medium IS NOT DISTINCT FROM k.utm_medium
   AND v.utm_campaign IS NOT DISTINCT FROM k.utm_campaign
LEFT JOIN spend_agg sp
    ON sp.visit_date = k.visit_date
   AND sp.utm_source IS NOT DISTINCT FROM k.utm_source
   AND sp.utm_medium IS NOT DISTINCT FROM k.utm_medium
   AND sp.utm_campaign IS NOT DISTINCT FROM k.utm_campaign
LEFT JOIN leads_agg l
    ON l.visit_date = k.visit_date
   AND l.utm_source IS NOT DISTINCT FROM k.utm_source
   AND l.utm_medium IS NOT DISTINCT FROM k.utm_medium
   AND l.utm_campaign IS NOT DISTINCT FROM k.utm_campaign
ORDER BY
    l.revenue DESC NULLS LAST,
    k.visit_date ASC,
    v.visitors_count DESC,
    k.utm_source ASC,
    k.utm_medium ASC,
    k.utm_campaign ASC;