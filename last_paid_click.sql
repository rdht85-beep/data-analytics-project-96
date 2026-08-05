WITH 
paid_sessions_ranked AS (
    SELECT 
        visitor_id,
        visit_date,
        source,
        medium,
        campaign,
        ROW_NUMBER() OVER (PARTITION BY visitor_id ORDER BY visit_date ASC) as session_seq
    FROM sessions
    WHERE LOWER(medium) IN ('cpc', 'cpm', 'cpa', 'youtube', 'cpp', 'tg', 'social')
),

leads_with_attributed_session AS (
    SELECT 
        l.lead_id,
        l.visitor_id,
        l.created_at,
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
        ) as attributed_session_seq
    FROM leads l
),

combined_data AS (
    SELECT 
        s.visitor_id,
        s.visit_date,
        s.source,
        s.medium,
        s.campaign,
        l.lead_id,
        l.created_at,
        l.amount,
        l.closing_reason,
        l.status_id
    FROM paid_sessions_ranked s
    LEFT JOIN leads_with_attributed_session l 
        ON s.visitor_id = l.visitor_id 
       AND s.session_seq = l.attributed_session_seq
)

SELECT 
    visitor_id,
    visit_date,
    source,
    medium,
    campaign,
    lead_id,
    created_at,
    amount,
    closing_reason,
    status_id
FROM combined_data
ORDER BY 
    amount DESC NULLS LAST,
    visit_date ASC,
    source ASC,
    medium ASC,
    campaign ASC;
