WITH sessions_flagged AS (
    SELECT
        visitor_id,
        source,
        medium,
        campaign,
        visit_date
    FROM sessions s
    WHERE s.medium IN ('cpc','cpm','cpa','youtube','cpp','tg','social')
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

last_paid_no_lead_ranked AS (
    SELECT
        s.visitor_id,
        s.visit_date,
        s.source   AS utm_source,
        s.medium   AS utm_medium,
        s.campaign AS utm_campaign,
        NULL::varchar   AS lead_id,
        NULL::timestamp AS created_at,
        NULL::integer   AS amount,
        NULL::varchar   AS closing_reason,
        NULL::bigint    AS status_id,
        ROW_NUMBER() OVER (
            PARTITION BY s.visitor_id
            ORDER BY s.visit_date DESC
        ) AS rn
    FROM sessions_flagged s
    WHERE s.visitor_id NOT IN (SELECT visitor_id FROM leads)
),
last_paid_no_lead AS (
    SELECT
        visitor_id, visit_date, utm_source, utm_medium, utm_campaign,
        lead_id, created_at, amount, closing_reason, status_id
    FROM last_paid_no_lead_ranked
    WHERE rn = 1
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