-- Весь трафик сайта (ВСЕ medium без исключений, включая organic)
SELECT
    visit_date::date AS visit_date,
    COALESCE(source, 'direct/none') AS utm_source,
    COALESCE(medium, 'none')        AS utm_medium,
    COALESCE(campaign, 'none')      AS utm_campaign,
    COUNT(DISTINCT visitor_id)      AS visitors_count
FROM sessions
GROUP BY
    visit_date::date,
    COALESCE(source, 'direct/none'),
    COALESCE(medium, 'none'),
    COALESCE(campaign, 'none')
ORDER BY
    visit_date ASC,
    visitors_count DESC;


-- Даты старта/окончания рекламных кампаний (для вспомогательной таблицы в Preset. Сдвиг по времени понадобился для корректного отображения в чартах для даты 01.06.2023)
SELECT
    utm_campaign,
    utm_source,
    utm_medium,
    MIN(campaign_date) AS campaign_start_date_original,
    MIN(campaign_date) + INTERVAL '12 hours' AS campaign_start_date_shifted
FROM (
    SELECT campaign_date, utm_source, utm_medium, utm_campaign
    FROM vk_ads
    UNION ALL
    SELECT campaign_date, utm_source, utm_medium, utm_campaign
    FROM ya_ads
) all_ads
GROUP BY utm_campaign, utm_source, utm_medium
ORDER BY campaign_start_date_original ASC;


-- Доходы вне платных каналов (органика)
WITH unique_leads AS (
    SELECT DISTINCT
        s.visitor_id,
        s.source,
        s.medium,
        l.lead_id,
        l.amount
    FROM sessions s
    LEFT JOIN leads l 
        ON s.visitor_id = l.visitor_id
        AND l.created_at >= s.visit_date
    WHERE s.medium = 'organic'
      AND s.source IS NOT NULL
      AND l.amount IS NOT NULL
)
SELECT  
    source,
    medium,
    SUM(amount) AS total_revenue
FROM unique_leads
GROUP BY source, medium
ORDER BY total_revenue DESC;


-- Остальные чарты в дашборде собраны на основе aggregate_last_paid_click (датасет all_metrics) и last_paid_click (датасет raw_data)