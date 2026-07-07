WITH 
last_paid_click AS (
    SELECT 
        l.lead_id,
        s.visit_date,
        s.source AS utm_source,
        s.medium AS utm_medium,
        s.campaign AS utm_campaign,
        ROW_NUMBER() OVER (PARTITION BY l.lead_id ORDER BY s.visit_date DESC) AS row_nmb
    FROM leads l
    JOIN sessions s ON l.visitor_id = s.visitor_id AND s.visit_date <= l.created_at
    WHERE s.medium IN ('cpc', 'cpm', 'cpa', 'youtube', 'cpp', 'tg', 'social')
)
SELECT 
    s.visitor_id,
    s.visit_date,
    COALESCE(lpc.utm_source, s.source) AS utm_source,
    COALESCE(lpc.utm_medium, s.medium) AS utm_medium,
    COALESCE(lpc.utm_campaign, s.campaign) AS utm_campaign,
    l.lead_id,
    l.created_at,
    l.amount,
    l.closing_reason,
    l.status_id
FROM sessions s
LEFT JOIN leads l 
    ON s.visitor_id = l.visitor_id 
   AND l.created_at >= s.visit_date
LEFT JOIN last_paid_click lpc 
    ON l.lead_id = lpc.lead_id AND lpc.row_nmb = 1
ORDER BY 
    l.amount DESC NULLS LAST,
    s.visit_date ASC,
    utm_source ASC,
    utm_medium ASC,
    utm_campaign ASC;
