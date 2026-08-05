-- Пользователи и конверсия с разделением на группы по сессиям и без них (direct) + конверсия
WITH group_data AS (
    -- 1: уникальные пользователи из таблицы sessions
    SELECT 
        1 AS sort_order, -- Для правильной сортировки (итог снизу)
        'С сессиями' AS user_group,
        COUNT(DISTINCT s.visitor_id) AS unique_users_count,
        COUNT(DISTINCT l.visitor_id) AS unique_users_with_lead_count,
        SUM(COALESCE(l.leads_count, 0)) AS total_leads_count,
        SUM(COALESCE(l.sales_count, 0)) AS purchases_count
    FROM (
        SELECT DISTINCT visitor_id 
        FROM sessions
    ) s
    LEFT JOIN (
        SELECT 
            visitor_id,
            COUNT(lead_id) AS leads_count,
            COUNT(CASE WHEN status_id = '142' THEN lead_id END) AS sales_count -- 142 - статус "Успешная продажа"
        FROM leads
        GROUP BY visitor_id
    ) l ON s.visitor_id = l.visitor_id

    UNION ALL

    -- 2: Пользователи из leads, которых нет в таблице sessions
    SELECT 
        2 AS sort_order,
        'Без сессий' AS user_group,
        COUNT(DISTINCT l.visitor_id) AS unique_users_count,
        COUNT(DISTINCT l.visitor_id) AS unique_users_with_lead_count,
        COUNT(l.lead_id) AS total_leads_count,
        COUNT(CASE WHEN status_id = '142' THEN l.lead_id END) AS purchases_count
    FROM leads l
    WHERE NOT EXISTS (
        SELECT 1 
        FROM sessions s 
        WHERE s.visitor_id = l.visitor_id
    )
),
combined_data AS (
    SELECT 
        sort_order, user_group, unique_users_count, 
        unique_users_with_lead_count, total_leads_count, purchases_count
    FROM group_data
    
    UNION ALL
    
    SELECT 
        3 AS sort_order,
        'ИТОГО' AS user_group,
        SUM(unique_users_count) AS unique_users_count,
        SUM(unique_users_with_lead_count) AS unique_users_with_lead_count,
        SUM(total_leads_count) AS total_leads_count,
        SUM(purchases_count) AS purchases_count
    FROM group_data
)
SELECT 
    user_group,
    unique_users_count,
    total_leads_count,
    purchases_count,
    ROUND(
        purchases_count * 100.0 / NULLIF(total_leads_count, 0), 
        2
    ) AS lead_to_sale_cr
FROM combined_data
ORDER BY sort_order;


-- Таблица для расчета основных метрик для дашборда в Preset
WITH

ads AS (
    SELECT
        utm_source,
        utm_medium,
        utm_campaign,
        campaign_date::date AS spend_date,
        daily_spent
    FROM vk_ads

    UNION ALL

    SELECT
        utm_source,
        utm_medium,
        utm_campaign,
        campaign_date::date AS spend_date,
        daily_spent
    FROM ya_ads
),

spend_agg AS (
    SELECT
        spend_date,
        utm_source,
        utm_medium,
        utm_campaign,
        SUM(daily_spent) AS total_cost
    FROM ads
    GROUP BY spend_date, utm_source, utm_medium, utm_campaign
),

visits AS (
    SELECT
        visitor_id,
        source       AS utm_source,
        medium       AS utm_medium,
        campaign     AS utm_campaign,
        visit_date::date AS visit_date
    FROM sessions
),

visitors_agg AS (
    SELECT
        visit_date,
        utm_source,
        utm_medium,
        utm_campaign,
        COUNT(DISTINCT visitor_id) AS visitors_count
    FROM visits
    GROUP BY visit_date, utm_source, utm_medium, utm_campaign
),

lead_attribution AS (
    SELECT
        l.lead_id,
        l.visitor_id,
        l.amount,
        l.created_at::date AS lead_date,
        l.status_id,
        v.utm_source,
        v.utm_medium,
        v.utm_campaign,
        ROW_NUMBER() OVER (
            PARTITION BY l.lead_id
            ORDER BY v.visit_date DESC
        ) AS rn
    FROM leads l
    LEFT JOIN visits v
        ON v.visitor_id = l.visitor_id
       AND v.visit_date <= l.created_at
),

lead_attributed AS (
    SELECT *
    FROM lead_attribution
    WHERE rn = 1
),

leads_agg AS (
    SELECT
        lead_date,
        utm_source,
        utm_medium,
        utm_campaign,
        COUNT(DISTINCT lead_id) AS leads_count
    FROM lead_attributed
    GROUP BY lead_date, utm_source, utm_medium, utm_campaign
),

purchases_agg AS (
    SELECT
        lead_date,
        utm_source,
        utm_medium,
        utm_campaign,
        COUNT(DISTINCT lead_id) AS purchases_count,
        SUM(amount)             AS revenue
    FROM lead_attributed
    WHERE status_id = '142'
    GROUP BY lead_date, utm_source, utm_medium, utm_campaign
)

SELECT
    COALESCE(v.visit_date, s.spend_date, l.lead_date, p.lead_date) AS report_date,
    COALESCE(v.utm_source, s.utm_source, l.utm_source, p.utm_source, 'unknown')     AS utm_source,
    COALESCE(v.utm_medium, s.utm_medium, l.utm_medium, p.utm_medium, 'unknown')     AS utm_medium,
    COALESCE(v.utm_campaign, s.utm_campaign, l.utm_campaign, p.utm_campaign, 'unknown') AS utm_campaign,

    COALESCE(v.visitors_count, 0)   AS visitors_count,
    COALESCE(l.leads_count, 0)      AS leads_count,
    COALESCE(p.purchases_count, 0)  AS purchases_count,
    COALESCE(s.total_cost, 0)       AS total_cost,
    COALESCE(p.revenue, 0)          AS revenue

FROM visitors_agg v
FULL OUTER JOIN spend_agg s
    ON  v.visit_date   = s.spend_date
    AND v.utm_source   = s.utm_source
    AND v.utm_medium   = s.utm_medium
    AND v.utm_campaign = s.utm_campaign
FULL OUTER JOIN leads_agg l
    ON  COALESCE(v.visit_date, s.spend_date) = l.lead_date
    AND COALESCE(v.utm_source, s.utm_source) = l.utm_source
    AND COALESCE(v.utm_medium, s.utm_medium) = l.utm_medium
    AND COALESCE(v.utm_campaign, s.utm_campaign) = l.utm_campaign
FULL OUTER JOIN purchases_agg p
    ON  COALESCE(v.visit_date, s.spend_date, l.lead_date) = p.lead_date
    AND COALESCE(v.utm_source, s.utm_source, l.utm_source) = p.utm_source
    AND COALESCE(v.utm_medium, s.utm_medium, l.utm_medium) = p.utm_medium
    AND COALESCE(v.utm_campaign, s.utm_campaign, l.utm_campaign) = p.utm_campaign

ORDER BY report_date, utm_source, utm_medium, utm_campaign;