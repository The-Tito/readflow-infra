-- Vistas de retención
CREATE OR REPLACE VIEW view_user_retention_stats AS
SELECT
    u.id                                    AS user_id,
    u.username,
    COUNT(DISTINCT ss.id)                   AS total_sessions,
    COUNT(DISTINCT CASE WHEN a_t0.id IS NOT NULL THEN ss.id END) AS sessions_with_t0,
    COUNT(DISTINCT CASE WHEN a_t48.id IS NOT NULL THEN ss.id END) AS sessions_with_t48,
    ROUND(AVG(a_t0.score)::numeric, 1)      AS avg_score_t0,
    ROUND(AVG(a_t48.score)::numeric, 1)     AS avg_score_t48,
    ROUND(AVG(a_t48.iri_value)::numeric, 1) AS avg_iri,
    ROUND(MAX(a_t48.iri_value)::numeric, 1) AS best_iri,
    ROUND(AVG(a_t48.score - a_t0.score)::numeric, 1) AS avg_score_improvement,
    MAX(GREATEST(
        COALESCE(a_t0.completed_at, '1970-01-01'),
        COALESCE(a_t48.completed_at, '1970-01-01')
    )) AS last_activity_at
FROM users u
LEFT JOIN study_sessions ss ON u.id = ss.user_id
LEFT JOIN attempts a_t0 ON ss.id = a_t0.study_session_id AND a_t0.timing_tag = 'T0' AND a_t0.completed_at IS NOT NULL
LEFT JOIN attempts a_t48 ON ss.id = a_t48.study_session_id AND a_t48.timing_tag = 'T48' AND a_t48.completed_at IS NOT NULL
GROUP BY u.id, u.username;

CREATE OR REPLACE VIEW view_session_iri_timeline AS
SELECT
    ss.id                                         AS session_id,
    ss.user_id,
    ss.title,
    ss.created_at,
    dl.display_name                               AS difficulty_level,
    et.display_name                               AS evaluation_type,
    a_t0.score                                    AS score_t0,
    a_t48.score                                   AS score_t48,
    a_t48.iri_value                               AS iri,
    ROUND((a_t48.score - a_t0.score)::numeric, 1) AS score_improvement
FROM study_sessions ss
JOIN difficulty_levels dl ON ss.difficulty_level_id = dl.id
JOIN evaluation_types et ON ss.evaluation_type_id = et.id
LEFT JOIN attempts a_t0 ON ss.id = a_t0.study_session_id AND a_t0.timing_tag = 'T0' AND a_t0.completed_at IS NOT NULL
LEFT JOIN attempts a_t48 ON ss.id = a_t48.study_session_id AND a_t48.timing_tag = 'T48' AND a_t48.completed_at IS NOT NULL
ORDER BY ss.created_at ASC;

-- Vista para hipótesis (stats globales de la plataforma)
CREATE OR REPLACE VIEW view_hypothesis_metrics AS
WITH base_data AS (
    SELECT 
        u.id AS user_id,
        ss.id AS session_id,
        dl.display_name AS difficulty_level,
        fn_get_session_status(ss.id) AS session_status,
        a_t0.score AS t0_score,
        a_t48.score AS t48_score,
        a_t48.iri_value AS iri_value
    FROM users u
    LEFT JOIN study_sessions ss ON u.id = ss.user_id
    LEFT JOIN difficulty_levels dl ON ss.difficulty_level_id = dl.id
    LEFT JOIN attempts a_t0 ON ss.id = a_t0.study_session_id AND a_t0.timing_tag = 'T0' AND a_t0.completed_at IS NOT NULL
    LEFT JOIN attempts a_t48 ON ss.id = a_t48.study_session_id AND a_t48.timing_tag = 'T48' AND a_t48.completed_at IS NOT NULL
)
SELECT 
    COUNT(DISTINCT user_id) AS total_users,
    
    COUNT(DISTINCT CASE WHEN session_status = 'completed' THEN session_id END) AS total_completed_sessions,
    
    ROUND((COUNT(DISTINCT CASE WHEN t48_score IS NOT NULL THEN user_id END)::numeric / 
           NULLIF(COUNT(DISTINCT user_id), 0)) * 100, 2) AS system_retention_rate,
           
    ROUND(COALESCE(AVG(CASE WHEN session_status = 'completed' THEN iri_value END), 0)::numeric, 2) AS global_avg_iri,
    
    ROUND(COALESCE(AVG(CASE WHEN session_status = 'completed' THEN (t48_score - t0_score) END), 0)::numeric, 2) AS avg_score_improvement,
    
    (SELECT jsonb_object_agg(difficulty_level, session_count)
     FROM (
         SELECT difficulty_level, COUNT(DISTINCT session_id) AS session_count
         FROM base_data
         WHERE session_status = 'completed' AND difficulty_level IS NOT NULL
         GROUP BY difficulty_level
     ) AS diff_stats
    ) AS difficulty_distribution
FROM base_data;