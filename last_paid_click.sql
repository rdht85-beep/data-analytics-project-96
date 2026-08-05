WITH sessions_flagged AS (
    SELECT
        visitor_id,
        source,
        medium,
        campaign,
        visit_date,
        (medium IN ('cpc','cpm','cpa','youtube','cpp','tg','social')) AS is_paid
    FROM sessions
),

last_paid_for_lead AS (
    SELECT DISTINCT ON (l.lead_id)
        s.visitor_id,
        s.visit_date,
        s.source   AS utm_source,
        s.medium   AS utm_medium,
        s.campaign AS utm_campaign,
        l.lead_id,
        l.created_at,
        l.amount,
        l.closing_reason,
        l.status_id
    FROM leads l
    JOIN sessions_flagged s
        ON s.visitor_id = l.visitor_id
       AND s.is_paid
       AND s.visit_date <= l.created_at
    ORDER BY l.lead_id, s.visit_date DESC
),

last_paid_no_lead AS (
    SELECT DISTINCT ON (s.visitor_id)
        s.visitor_id,
        s.visit_date,
        s.source   AS utm_source,
        s.medium   AS utm_medium,
        s.campaign AS utm_campaign,
        NULL::varchar   AS lead_id,
        NULL::timestamp AS created_at,
        NULL::integer   AS amount,
        NULL::varchar   AS closing_reason,
        NULL::bigint    AS status_id
    FROM sessions_flagged s
    WHERE s.is_paid
      AND s.visitor_id NOT IN (SELECT visitor_id FROM leads)
    ORDER BY s.visitor_id, s.visit_date DESC
)

SELECT * FROM last_paid_for_lead
UNION ALL
SELECT * FROM last_paid_no_lead
ORDER BY
    amount DESC NULLS LAST,
    visit_date ASC,
    utm_source ASC,
    utm_medium ASC,
    utm_campaign ASC;