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

last_paid_click AS (
    SELECT 
        visit_date::date,
        utm_source,
        utm_medium,
        utm_campaign,
        lead_id,
        amount,
        status_id,
        visitor_id
    FROM (
    	SELECT 
            s.visit_date,
            s.source AS utm_source,
            s.medium AS utm_medium,
            s.campaign AS utm_campaign,
            l.lead_id,
            l.amount,
            l.status_id,
            s.visitor_id,
            ROW_NUMBER() OVER (PARTITION BY l.lead_id ORDER BY s.visit_date DESC) AS rn
        FROM leads l
        JOIN sessions_flagged s
            ON s.visitor_id = l.visitor_id
            AND s.visit_date <= l.created_at
    ) ranked
    WHERE rn = 1
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

final AS (
    SELECT
        lpc.visit_date,
        COUNT(lpc.visitor_id) AS visitors_count,
        lpc.utm_source,
        lpc.utm_medium,
        lpc.utm_campaign,
        sp.total_cost,
        COUNT(DISTINCT lpc.lead_id) AS leads_count,
        COUNT(DISTINCT lpc.lead_id) FILTER (WHERE lpc.status_id = 142) AS purchases_count,
        SUM(lpc.amount) FILTER (WHERE lpc.status_id = 142) AS revenue
    FROM last_paid_click lpc
    LEFT JOIN spend_agg sp
        ON sp.visit_date = lpc.visit_date
        AND sp.utm_source = lpc.utm_source
        AND sp.utm_medium = lpc.utm_medium
        AND sp.utm_campaign = lpc.utm_campaign
    GROUP BY 1, 3, 4, 5, sp.total_cost
)

SELECT *
FROM final
ORDER BY 
    revenue DESC NULLS LAST,
    visit_date ASC,
    visitors_count DESC,
    utm_source ASC,
    utm_medium ASC,
    utm_campaign ASC;