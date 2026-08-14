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

leads_visits_agg AS (
    SELECT
        visit_date::date,
        utm_source,
        utm_medium,
        utm_campaign,
        COUNT(visitor_id) AS visitors_count,
        COUNT(DISTINCT lead_id) AS leads_count,
        COUNT(DISTINCT lead_id) FILTER (WHERE status_id = 142) AS purchases_count,
        SUM(amount) FILTER (WHERE status_id = 142) AS revenue
    FROM last_paid_click
    GROUP BY visit_date::date, utm_source, utm_medium, utm_campaign
),

ads_spend_agg AS (
    SELECT
        campaign_date::date AS visit_date,
        utm_source,
        utm_medium,
        utm_campaign,
        SUM(daily_spent) AS total_cost
    FROM (
        SELECT campaign_date, utm_source, utm_medium, utm_campaign, daily_spent
        FROM vk_ads
        UNION ALL
        SELECT campaign_date, utm_source, utm_medium, utm_campaign, daily_spent
        FROM ya_ads
    ) all_ads
    GROUP BY campaign_date::date, utm_source, utm_medium, utm_campaign
)

SELECT
    lva.visit_date,
    lva.visitors_count,
    lva.utm_source,
    lva.utm_medium,
    lva.utm_campaign,
    asa.total_cost,
    lva.leads_count,
    lva.purchases_count,
    lva.revenue
FROM leads_visits_agg lva
LEFT JOIN ads_spend_agg asa
    ON asa.visit_date = lva.visit_date
    AND asa.utm_source = lva.utm_source
    AND asa.utm_medium = lva.utm_medium
    AND asa.utm_campaign = lva.utm_campaign
ORDER BY 
    lva.revenue DESC NULLS LAST,
    lva.visit_date ASC,
    lva.visitors_count DESC,
    lva.utm_source ASC,
    lva.utm_medium ASC,
    lva.utm_campaign ASC;