WITH 
marketing_costs AS (
    SELECT 
        campaign_date AS ad_date,
        utm_source,
        utm_medium,
        utm_campaign,
        SUM(daily_spent) AS total_cost
    FROM vk_ads
    GROUP BY 1, 2, 3, 4
    
    UNION ALL
    
    SELECT 
        campaign_date AS ad_date,
        utm_source,
        utm_medium,
        utm_campaign,
        SUM(daily_spent) AS total_cost
    FROM ya_ads
    GROUP BY 1, 2, 3, 4
),

sessions_and_leads AS (
    SELECT 
        CAST(s.visit_date AS DATE) AS session_date,
        s.source AS utm_source,
        s.medium AS utm_medium,
        s.campaign AS utm_campaign,
        COUNT(s.visitor_id) AS visitors_count,
        COUNT(l.lead_id) AS leads_count,
        COUNT(CASE WHEN l.closing_reason = 'Успешно реализовано' OR l.status_id = 142 THEN l.lead_id END) AS purchases_count,
        SUM(CASE WHEN l.closing_reason = 'Успешно реализовано' OR l.status_id = 142 THEN l.amount ELSE 0 END) AS revenue
    FROM sessions s
    LEFT JOIN leads l ON s.visitor_id = l.visitor_id
    GROUP BY 1, 2, 3, 4
),

final_mart_tab AS (
    SELECT 
        COALESCE(c.ad_date, sl.session_date) AS visit_date,
        COALESCE(c.utm_source, sl.utm_source) AS utm_source,
        COALESCE(c.utm_medium, sl.utm_medium) AS utm_medium,
        COALESCE(c.utm_campaign, sl.utm_campaign) AS utm_campaign,
        COALESCE(sl.visitors_count, 0) AS visitors_count,
        COALESCE(c.total_cost, 0) AS total_cost,
        COALESCE(sl.leads_count, 0) AS leads_count,
        COALESCE(sl.purchases_count, 0) AS purchases_count,
        COALESCE(sl.revenue, 0) AS revenue
    FROM marketing_costs c
    FULL JOIN sessions_and_leads sl 
        ON c.ad_date = sl.session_date
       AND c.utm_source = sl.utm_source
       AND c.utm_medium = sl.utm_medium
       AND c.utm_campaign = sl.utm_campaign
)

SELECT 
    visit_date,
    visitors_count,
    utm_source,
    utm_medium,
    utm_campaign,
    total_cost,
    leads_count,
    purchases_count,
    revenue
FROM final_mart_tab
ORDER BY 
    revenue DESC NULLS LAST,
    visit_date ASC, 
    visitors_count DESC,
    utm_source ASC,     
    utm_medium ASC, 
    utm_campaign ASC;