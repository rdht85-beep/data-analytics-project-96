WITH 
vk_costs AS (
    SELECT 
        campaign_date AS visit_date,
        LOWER(utm_source) AS utm_source,
        LOWER(utm_medium) AS utm_medium,
        LOWER(utm_campaign) AS utm_campaign,
        SUM(daily_spent) AS total_cost
    FROM vk_ads
    GROUP BY campaign_date, LOWER(utm_source), LOWER(utm_medium), LOWER(utm_campaign)
),

ya_costs AS (
    SELECT 
        campaign_date AS visit_date,
        LOWER(utm_source) AS utm_source,
        LOWER(utm_medium) AS utm_medium,
        LOWER(utm_campaign) AS utm_campaign,
        SUM(daily_spent) AS total_cost
    FROM ya_ads
    GROUP BY campaign_date, LOWER(utm_source), LOWER(utm_medium), LOWER(utm_campaign)
),

all_costs AS (
    SELECT visit_date, utm_source, utm_medium, utm_campaign, total_cost FROM vk_costs
    UNION ALL
    SELECT visit_date, utm_source, utm_medium, utm_campaign, total_cost FROM ya_costs
),

total_costs_aggregated AS (
    SELECT 
        visit_date,
        utm_source,
        utm_medium,
        utm_campaign,
        SUM(total_cost) AS total_cost
    FROM all_costs
    GROUP BY visit_date, utm_source, utm_medium, utm_campaign
),

paid_sessions_ranked AS (
    SELECT 
        visitor_id,
        visit_date,
        CAST(visit_date AS DATE) AS visit_day,
        LOWER(source) AS utm_source,
        LOWER(medium) AS utm_medium,
        LOWER(campaign) AS utm_campaign,
        ROW_NUMBER() OVER (PARTITION BY visitor_id ORDER BY visit_date ASC) as session_seq
    FROM sessions
    WHERE LOWER(medium) IN ('cpc', 'cpm', 'cpa', 'youtube', 'cpp', 'tg', 'social')
),

leads_with_attributed_session AS (
    SELECT 
        l.lead_id,
        l.amount,
        l.closing_reason,
        l.status_id,
        (
            SELECT s.session_seq
            FROM paid_sessions_ranked s
            WHERE s.visitor_id = l.visitor_id 
              AND s.visit_date <= l.created_at
            ORDER BY s.visit_date DESC
            LIMIT 1
        ) as attributed_session_seq,
        l.visitor_id
    FROM leads l
),

traffic_and_leads_stats AS (
    SELECT 
        s.visit_day AS visit_date,
        s.utm_source,
        s.utm_medium,
        s.utm_campaign,
        COUNT(s.visitor_id) AS visitors_count,
        COUNT(l.lead_id) AS leads_count,
        COUNT(CASE WHEN l.status_id = '142' THEN l.lead_id END) AS purchases_count,
        SUM(CASE WHEN l.status_id = '142' THEN l.amount END) AS revenue
    FROM paid_sessions_ranked s
    LEFT JOIN leads_with_attributed_session l 
        ON s.visitor_id = l.visitor_id 
       AND s.session_seq = l.attributed_session_seq
    GROUP BY s.visit_day, s.utm_source, s.utm_medium, s.utm_campaign
),

final_mart AS (
    SELECT 
        COALESCE(t.visit_date, c.visit_date) AS visit_date,
        COALESCE(t.utm_source, c.utm_source) AS utm_source,
        COALESCE(t.utm_medium, c.utm_medium) AS utm_medium,
        COALESCE(t.utm_campaign, c.utm_campaign) AS utm_campaign,
        COALESCE(t.visitors_count, 0) AS visitors_count,
        COALESCE(c.total_cost, 0) AS total_cost,
        COALESCE(t.leads_count, 0) AS leads_count,
        COALESCE(t.purchases_count, 0) AS purchases_count,
        COALESCE(t.revenue, 0) AS revenue
    FROM traffic_and_leads_stats t
    FULL OUTER JOIN total_costs_aggregated c 
        ON t.visit_date = c.visit_date 
       AND t.utm_source = c.utm_source 
       AND t.utm_medium = c.utm_medium 
       AND t.utm_campaign = c.utm_campaign
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
FROM final_mart
ORDER BY 
    revenue DESC NULLS LAST,
    visit_date ASC,
    visitors_count DESC,
    utm_source ASC,
    utm_medium ASC,
    utm_campaign ASC;
