-- ============================================================
-- Readflow — Stored Procedures
-- Ejecutar en Supabase SQL Editor / BD local
-- ============================================================


-- ============================================================
-- SP 1: sp_register_attempt
-- Registra un attempt y actualiza métricas de IRI en user_streaks
-- Lógica compleja: valida timing, calcula IRI, actualiza métricas
-- El trigger trg_update_streak_on_attempt maneja current_streak
-- y best_streak. Este SP maneja average_iri, best_iri y
-- total_t48_completed que son cálculos propios del dominio IRI.
-- ============================================================

CREATE OR REPLACE PROCEDURE sp_register_attempt(
  p_user_id          INT,
  p_session_id       INT,
  p_timing_tag       VARCHAR,
  p_score            FLOAT,
  p_iri_value        FLOAT DEFAULT NULL
)
LANGUAGE plpgsql AS $$
DECLARE
  v_session        RECORD;
  v_existing       RECORD;
  v_t0_attempt     RECORD;
  v_streak         RECORD;
  v_prev_total     INT;
  v_prev_avg       FLOAT;
  v_prev_best      FLOAT;
  v_new_avg        FLOAT;
  v_new_best       FLOAT;
BEGIN
  -- Validar que la sesión existe y pertenece al usuario
  SELECT id, user_id INTO v_session
  FROM study_sessions
  WHERE id = p_session_id AND user_id = p_user_id;

  IF NOT FOUND THEN
    RAISE EXCEPTION 'SESION_NO_ENCONTRADA_O_ACCESO_DENEGADO';
  END IF;

  -- Validar que el timing_tag sea válido
  IF p_timing_tag NOT IN ('T0', 'T48') THEN
    RAISE EXCEPTION 'TIMING_TAG_INVALIDO: debe ser T0 o T48';
  END IF;

  -- Validar que no exista ya un attempt para este timing
  SELECT id INTO v_existing
  FROM attempts
  WHERE study_session_id = p_session_id AND timing_tag = p_timing_tag;

  IF FOUND THEN
    RAISE EXCEPTION 'INTENTO_YA_REGISTRADO para timing %', p_timing_tag;
  END IF;

  -- Validar que si es T48, ya exista un T0 completado
  IF p_timing_tag = 'T48' THEN
    SELECT id, score INTO v_t0_attempt
    FROM attempts
    WHERE study_session_id = p_session_id
      AND timing_tag = 'T0'
      AND completed_at IS NOT NULL;

    IF NOT FOUND THEN
      RAISE EXCEPTION 'T0_NO_COMPLETADO: no se puede registrar T48 sin T0 previo';
    END IF;
  END IF;

  -- Insertar el attempt — el trigger trg_update_streak_on_attempt
  -- se dispara automáticamente aquí y maneja current_streak y best_streak
  INSERT INTO attempts (
    user_id,
    study_session_id,
    timing_tag,
    user_answers,
    score,
    max_possible_score,
    iri_value,
    started_at,
    completed_at,
    grading_completed_at
  ) VALUES (
    p_user_id,
    p_session_id,
    p_timing_tag,
    '[]'::jsonb,   -- user_answers se maneja desde la API, aquí va vacío
    p_score,
    100.0,
    p_iri_value,
    NOW(),
    NOW(),
    NOW()
  );

  -- Si es T0: incrementar total_sessions
  IF p_timing_tag = 'T0' THEN
    UPDATE user_streaks
    SET total_sessions = total_sessions + 1
    WHERE user_id = p_user_id;
  END IF;

  -- Si es T48 con IRI válido: actualizar métricas de retención
  -- El trigger no maneja estas métricas porque son cálculos
  -- específicos del IRI, no del streak de actividad diaria
  IF p_timing_tag = 'T48' AND p_iri_value IS NOT NULL THEN
    SELECT average_iri, best_iri, total_t48_completed
    INTO v_streak
    FROM user_streaks
    WHERE user_id = p_user_id;

    v_prev_total := COALESCE(v_streak.total_t48_completed, 0);
    v_prev_avg   := COALESCE(v_streak.average_iri, 0);
    v_prev_best  := COALESCE(v_streak.best_iri, 0);

    -- Promedio incremental: no requiere recalcular todas las sesiones
    v_new_avg  := ROUND(((v_prev_avg * v_prev_total + p_iri_value) / (v_prev_total + 1))::numeric, 1);
    v_new_best := GREATEST(v_prev_best, p_iri_value);

    UPDATE user_streaks
    SET
      average_iri          = v_new_avg,
      best_iri             = v_new_best,
      total_t48_completed  = v_prev_total + 1
    WHERE user_id = p_user_id;
  END IF;

END;
$$;


-- ============================================================
-- SP 2: sp_create_study_session
-- ============================================================


-- ============================================================
-- SP 3: sp_generate_retention_report
-- Itera sobre todos los usuarios con cursor y genera un snapshot
-- de métricas de retención en la tabla retention_reports
-- Útil para análisis de hipótesis en un punto fijo del tiempo
-- ============================================================



CREATE OR REPLACE PROCEDURE sp_generate_retention_report()
LANGUAGE plpgsql AS $$
DECLARE
  -- Cursor que recorre todos los usuarios que tienen al menos una sesión
  v_cursor CURSOR FOR
    SELECT DISTINCT u.id AS user_id, u.username
    FROM users u
    JOIN study_sessions ss ON u.id = ss.user_id
    ORDER BY u.id;

  v_user          RECORD;
  v_total         INT;
  v_completed     INT;
  v_avg_iri       NUMERIC;
  v_best_iri      NUMERIC;
  v_avg_improve   NUMERIC;
  v_report_time   TIMESTAMPTZ := NOW();
BEGIN
  -- Limpiar reportes anteriores para evitar duplicados
  DELETE FROM retention_reports WHERE generated_at::DATE = CURRENT_DATE;

  -- Iterar sobre cada usuario con cursor
  OPEN v_cursor;

  LOOP
    FETCH v_cursor INTO v_user;
    EXIT WHEN NOT FOUND;

    -- Total de sesiones del usuario
    SELECT COUNT(*) INTO v_total
    FROM study_sessions
    WHERE user_id = v_user.user_id;

    -- Sesiones completamente terminadas (T0 + T48)
    SELECT COUNT(*) INTO v_completed
    FROM study_sessions ss
    WHERE ss.user_id = v_user.user_id
      AND fn_get_session_status(ss.id) = 'completed';

    -- Métricas de IRI usando la función tabular
    SELECT
      ROUND(AVG(iri), 1),
      ROUND(MAX(iri), 1),
      ROUND(AVG(score_improvement), 1)
    INTO v_avg_iri, v_best_iri, v_avg_improve
    FROM fn_get_user_retention_detail(v_user.user_id)
    WHERE status = 'completed';

    -- Insertar fila del reporte para este usuario
    INSERT INTO retention_reports (
      generated_at,
      user_id,
      username,
      total_sessions,
      completed_sessions,
      completion_rate,
      avg_iri,
      best_iri,
      avg_improvement
    ) VALUES (
      v_report_time,
      v_user.user_id,
      v_user.username,
      v_total,
      v_completed,
      CASE WHEN v_total > 0
        THEN ROUND((v_completed::numeric / v_total) * 100, 1)
        ELSE 0
      END,
      COALESCE(v_avg_iri, 0),
      COALESCE(v_best_iri, 0),
      COALESCE(v_avg_improve, 0)
    );

  END LOOP;

  CLOSE v_cursor;

  RAISE NOTICE 'Reporte generado a las % para % usuarios', v_report_time, (SELECT COUNT(*) FROM retention_reports WHERE generated_at = v_report_time);

END;
$$;


-- ============================================================
-- VERIFICAR QUE LOS SPs FUERON CREADOS
-- ============================================================
SELECT routine_name, routine_type
FROM information_schema.routines
WHERE routine_schema = 'public'
  AND routine_name IN (
    'sp_register_attempt',
    'sp_create_study_session',
    'sp_generate_retention_report'
  )
ORDER BY routine_name;
