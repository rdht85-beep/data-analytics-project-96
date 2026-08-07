WITH 

sessions_flagged AS (
    SELECT
        visitor_id,
        source,
        medium,
        campaign,
        visit_date
    FROM sessions s
    WHERE s.medium IN ('cpc','cpm','cpa','youtube','cpp','tg','social')
),

visits_agg AS (
    SELECT
        visit_date::date AS visit_date,
        source   AS utm_source,
        medium   AS utm_medium,
        campaign AS utm_campaign,
        COUNT(DISTINCT visitor_id) AS visitors_count
    FROM sessions_flagged
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
        l.created_at,
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
       AND s.visit_date <= l.created_at
),

last_paid_for_lead AS (
    SELECT
        visitor_id, visit_date, utm_source, utm_medium, utm_campaign,
        lead_id, created_at, amount, closing_reason, status_id
    FROM last_paid_for_lead_ranked
    WHERE rn = 1
),

leads_agg AS (
    SELECT
    	COUNT(visitor_id) AS visitors_count,
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
)

SELECT
    la.visit_date,
    v.visitors_count,
    la.utm_source,
    la.utm_medium,
    la.utm_campaign,
    sp.total_cost,
    leads_count,
    purchases_count,
    revenue
FROM leads_agg la
INNER  JOIN visits_agg v
    ON v.visit_date = la.visit_date
   AND v.utm_source IS NOT DISTINCT FROM la.utm_source
   AND v.utm_medium IS NOT DISTINCT FROM la.utm_medium
   AND v.utm_campaign IS NOT DISTINCT FROM la.utm_campaign
inner JOIN spend_agg sp
    ON sp.visit_date = la.visit_date
   AND sp.utm_source IS NOT DISTINCT FROM la.utm_source
   AND sp.utm_medium IS NOT DISTINCT FROM la.utm_medium
   AND sp.utm_campaign IS NOT DISTINCT FROM la.utm_campaign
ORDER BY
    revenue DESC NULLS LAST,
    la.visit_date ASC,
    visitors_count DESC,
    la.utm_source ASC,
    la.utm_medium ASC,
    la.utm_campaign ASC;