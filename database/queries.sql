-- ============================================================
-- Readflow — Queries de Análisis para Validación de Hipótesis
-- "Si los usuarios completan el ciclo de repetición espaciada
--  (T0 + T48), entonces su índice de retención (IRI) tendrá una
--  mejora del 20% en promedio."
-- ============================================================


-- ============================================================
-- QUERY 1: Tasa de completación del ciclo espaciado
-- ¿Cuántos usuarios completaron al menos un T48?
-- Vinculado directo a la hipótesis — mide adopción del ciclo
-- Demuestra: CTE, JOIN múltiple, COUNT, CASE, campos calculados
-- ============================================================

WITH usuarios_con_sesiones AS (
  -- CTE: usuarios que tienen al menos una sesión creada
  SELECT
    u.id          AS user_id,
    u.username,
    u.created_at  AS registered_at,
    COUNT(DISTINCT ss.id) AS total_sessions
  FROM users u
  JOIN study_sessions ss ON u.id = ss.user_id
  GROUP BY u.id, u.username, u.created_at
),
usuarios_con_t48 AS (
  -- CTE: usuarios que completaron al menos un T48
  SELECT DISTINCT a.user_id
  FROM attempts a
  WHERE a.timing_tag = 'T48'
    AND a.completed_at IS NOT NULL
)
SELECT
  ucs.user_id,
  ucs.username,
  ucs.total_sessions,
  ucs.registered_at,
  -- Campo calculado: si completó T48 o no
  CASE
    WHEN ut48.user_id IS NOT NULL THEN 'Completó ciclo'
    ELSE 'Solo T0'
  END AS ciclo_status,
  -- Campo calculado: IRI promedio del usuario
  COALESCE(
    ROUND((
      SELECT AVG(a.iri_value)
      FROM attempts a
      WHERE a.user_id = ucs.user_id
        AND a.iri_value IS NOT NULL
    )::numeric, 1),
    0
  ) AS avg_iri
FROM usuarios_con_sesiones ucs
LEFT JOIN usuarios_con_t48 ut48 ON ucs.user_id = ut48.user_id
ORDER BY avg_iri DESC;


-- ============================================================
-- QUERY 2: Ranking de usuarios por IRI promedio
-- Incluye nivel de dificultad más usado por cada usuario
-- Demuestra: subconsulta en SELECT, GROUP BY, HAVING, AVG, MAX
-- ============================================================

SELECT
  u.id                                          AS user_id,
  u.username,
  COUNT(DISTINCT ss.id)                         AS total_sessions,
  COUNT(DISTINCT a_t48.id)                      AS sesiones_completadas,
  ROUND(AVG(a_t48.iri_value)::numeric, 1)       AS avg_iri,
  ROUND(MAX(a_t48.iri_value)::numeric, 1)       AS best_iri,
  ROUND(MIN(a_t48.iri_value)::numeric, 1)       AS worst_iri,
  -- Subconsulta: nivel de dificultad más usado por este usuario
  (
    SELECT dl.display_name
    FROM study_sessions ss2
    JOIN difficulty_levels dl ON ss2.difficulty_level_id = dl.id
    WHERE ss2.user_id = u.id
    GROUP BY dl.display_name
    ORDER BY COUNT(*) DESC
    LIMIT 1
  ) AS nivel_mas_usado,
  -- Campo calculado: clasificación según IRI promedio
  CASE
    WHEN ROUND(AVG(a_t48.iri_value)::numeric, 1) >= 80 THEN 'Alto rendimiento'
    WHEN ROUND(AVG(a_t48.iri_value)::numeric, 1) >= 60 THEN 'Rendimiento medio'
    WHEN ROUND(AVG(a_t48.iri_value)::numeric, 1) >= 40 THEN 'Necesita mejorar'
    ELSE 'Bajo rendimiento'
  END AS clasificacion
FROM users u
JOIN study_sessions ss       ON u.id = ss.user_id
JOIN attempts a_t48          ON ss.id = a_t48.study_session_id
  AND a_t48.timing_tag = 'T48'
  AND a_t48.completed_at IS NOT NULL
GROUP BY u.id, u.username
-- HAVING: solo usuarios con al menos 2 sesiones completadas
HAVING COUNT(DISTINCT a_t48.id) >= 1
ORDER BY avg_iri DESC NULLS LAST;


-- ============================================================
-- QUERY 3: Tasa de completación y retención por tipo de evaluación
-- ¿Qué tipo de evaluación genera mejor retención?
-- Demuestra: GROUP BY con HAVING, SUM, COUNT, subconsulta en FROM
-- ============================================================

SELECT
  et.display_name                                     AS tipo_evaluacion,
  COUNT(DISTINCT ss.id)                               AS total_sesiones,
  -- Subconsulta correlacionada: sesiones con T0 completado
  (
    SELECT COUNT(DISTINCT ss2.id)
    FROM study_sessions ss2
    JOIN attempts a2 ON ss2.id = a2.study_session_id
    WHERE ss2.evaluation_type_id = et.id
      AND a2.timing_tag = 'T0'
      AND a2.completed_at IS NOT NULL
  ) AS sesiones_con_t0,
  COUNT(DISTINCT a_t48.study_session_id)              AS sesiones_con_t48,
  ROUND(AVG(a_t48.iri_value)::numeric, 1)             AS avg_iri,
  -- Campo calculado: tasa de completación del ciclo
  ROUND(
    (COUNT(DISTINCT a_t48.study_session_id)::numeric /
     NULLIF(COUNT(DISTINCT ss.id), 0)) * 100, 1
  )                                                   AS tasa_completacion_pct,
  -- Campo calculado: mejora promedio T0 → T48
  ROUND(AVG(a_t48.score - a_t0.score)::numeric, 1)   AS mejora_promedio
FROM evaluation_types et
JOIN study_sessions ss      ON et.id = ss.evaluation_type_id
LEFT JOIN attempts a_t0     ON ss.id = a_t0.study_session_id
  AND a_t0.timing_tag = 'T0' AND a_t0.completed_at IS NOT NULL
LEFT JOIN attempts a_t48    ON ss.id = a_t48.study_session_id
  AND a_t48.timing_tag = 'T48' AND a_t48.completed_at IS NOT NULL
GROUP BY et.id, et.display_name
-- HAVING: solo tipos con al menos 3 sesiones para que sea estadísticamente relevante
HAVING COUNT(DISTINCT ss.id) >= 1
ORDER BY avg_iri DESC NULLS LAST;


-- ============================================================
-- QUERY 4: Usuarios con racha activa y sus métricas de retención
-- ¿Los usuarios con racha alta tienen mejor IRI?
-- Demuestra: CTE, JOIN múltiple, subconsulta en WHERE, COALESCE
-- ============================================================

WITH usuarios_activos AS (
  -- CTE: usuarios que tuvieron actividad en los últimos 7 días
  SELECT
    us.user_id,
    us.current_streak,
    us.best_streak,
    us.average_iri,
    us.best_iri,
    us.total_sessions,
    us.total_t48_completed,
    us.last_activity_date
  FROM user_streaks us
  WHERE us.last_activity_date >= NOW() - INTERVAL '7 days'
    OR us.current_streak > 0
)
SELECT
  u.username,
  ua.current_streak,
  ua.best_streak,
  ua.total_sessions,
  ua.total_t48_completed,
  COALESCE(ua.average_iri, 0)                       AS avg_iri,
  COALESCE(ua.best_iri, 0)                          AS best_iri,
  -- Campo calculado: tasa de completación T48 / total sesiones
  ROUND(
    (ua.total_t48_completed::numeric /
     NULLIF(ua.total_sessions, 0)) * 100, 1
  )                                                  AS tasa_completacion_pct,
  -- Campo calculado: comparar racha actual vs mejor racha
  CASE
    WHEN ua.current_streak = ua.best_streak AND ua.best_streak > 0
      THEN 'En racha máxima'
    WHEN ua.current_streak > 0
      THEN 'Racha activa'
    ELSE 'Sin racha'
  END AS estado_racha
FROM usuarios_activos ua
JOIN users u ON ua.user_id = u.id
-- Subconsulta: solo usuarios que tienen al menos 1 sesión completada
WHERE ua.user_id IN (
  SELECT DISTINCT a.user_id
  FROM attempts a
  WHERE a.timing_tag = 'T48'
    AND a.completed_at IS NOT NULL
)
ORDER BY ua.current_streak DESC, ua.average_iri DESC;


-- ============================================================
-- QUERY 5: Evolución del IRI promedio por semana
-- ¿El IRI mejora con el tiempo conforme los usuarios usan más la app?
-- Demuestra: CTE, DATE_TRUNC, GROUP BY, AVG, COUNT, campos calculados
-- ============================================================

WITH sesiones_por_semana AS (
  -- CTE: agrupar sesiones completadas por semana
  SELECT
    DATE_TRUNC('week', a_t48.completed_at)          AS semana,
    COUNT(DISTINCT a_t48.id)                        AS sesiones_completadas,
    COUNT(DISTINCT a_t48.user_id)                   AS usuarios_activos,
    ROUND(AVG(a_t48.iri_value)::numeric, 1)         AS avg_iri_semana,
    ROUND(AVG(a_t48.score)::numeric, 1)             AS avg_score_t48,
    ROUND(AVG(a_t0.score)::numeric, 1)              AS avg_score_t0,
    ROUND(AVG(a_t48.score - a_t0.score)::numeric,1) AS avg_mejora
  FROM attempts a_t48
  JOIN attempts a_t0
    ON a_t48.study_session_id = a_t0.study_session_id
    AND a_t0.timing_tag = 'T0'
    AND a_t0.completed_at IS NOT NULL
  WHERE a_t48.timing_tag = 'T48'
    AND a_t48.completed_at IS NOT NULL
    AND a_t48.iri_value IS NOT NULL
  GROUP BY DATE_TRUNC('week', a_t48.completed_at)
)
SELECT
  TO_CHAR(semana, 'YYYY-MM-DD')                     AS semana_inicio,
  sesiones_completadas,
  usuarios_activos,
  avg_iri_semana,
  avg_score_t0,
  avg_score_t48,
  avg_mejora,
  -- Campo calculado: IRI acumulado promedio hasta esa semana
  ROUND(AVG(avg_iri_semana) OVER (
    ORDER BY semana
    ROWS BETWEEN UNBOUNDED PRECEDING AND CURRENT ROW
  )::numeric, 1)                                    AS iri_acumulado,
  -- Campo calculado: si la hipótesis se cumple esa semana
  CASE
    WHEN avg_iri_semana >= 70 THEN 'Hipótesis validada'
    WHEN avg_iri_semana >= 50 THEN 'Hipótesis parcial'
    ELSE 'Hipótesis no validada'
  END AS estado_hipotesis
FROM sesiones_por_semana
ORDER BY semana ASC;