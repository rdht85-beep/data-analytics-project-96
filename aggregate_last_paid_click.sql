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
            ROW_NUMBER() OVER (PARTITION BY s.visitor_id ORDER BY s.visit_date DESC) AS rn
        FROM sessions_flagged s
        LEFT JOIN leads l
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
    lv.visit_date,
    lv.visitors_count,
    lv.utm_source,
    lv.utm_medium,
    lv.utm_campaign,
    a.total_cost,
    lv.leads_count,
    lv.purchases_count,
    lv.revenue
FROM leads_visits_agg lv
LEFT JOIN ads_spend_agg a
    ON a.visit_date = lv.visit_date
    AND a.utm_source = lv.utm_source
    AND a.utm_medium = lv.utm_medium
    AND a.utm_campaign = lv.utm_campaign
ORDER BY 
    lv.revenue DESC NULLS LAST,
    lv.visit_date ASC,
    lv.visitors_count DESC,
    lv.utm_source ASC,
    lv.utm_medium ASC,
    lv.utm_campaign ASC;