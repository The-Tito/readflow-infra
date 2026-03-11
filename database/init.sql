-- ============================================================
-- Readflow — Schema inicial de la base de datos
-- Este archivo se ejecuta automáticamente al crear el contenedor
-- ============================================================

-- Extensiones
CREATE EXTENSION IF NOT EXISTS "uuid-ossp";

-- ============================================================
-- TABLAS DE CATÁLOGO
-- ============================================================

-- Tabla de niveles de dificultad
CREATE TABLE IF NOT EXISTS difficulty_levels (
  id SERIAL PRIMARY KEY,
  slug VARCHAR(50) NOT NULL UNIQUE,
  display_name VARCHAR(100) NOT NULL,
  description TEXT
);

-- Tabla de tipos de evaluación
CREATE TABLE IF NOT EXISTS evaluation_types (
  id SERIAL PRIMARY KEY,
  slug VARCHAR(50) NOT NULL UNIQUE,
  display_name VARCHAR(100) NOT NULL,
  validation_schema JSONB,
  scoring_config JSONB
);

-- ============================================================
-- TABLAS PRINCIPALES
-- ============================================================

-- Tabla de usuarios
CREATE TABLE IF NOT EXISTS users (
  id SERIAL PRIMARY KEY,
  username VARCHAR(50) NOT NULL,
  email VARCHAR(255) NOT NULL UNIQUE,
  password VARCHAR(255),
  google_id VARCHAR(255) UNIQUE,
  avatar VARCHAR(500),
  created_at TIMESTAMPTZ DEFAULT NOW(),
  updated_at TIMESTAMPTZ DEFAULT NOW()
);

-- Tabla de documentos
CREATE TABLE IF NOT EXISTS documents (
  id SERIAL PRIMARY KEY,
  user_id INT NOT NULL REFERENCES users(id) ON DELETE CASCADE ON UPDATE CASCADE,
  document_hash VARCHAR(64) NOT NULL,
  original_filename VARCHAR(255) NOT NULL,
  uploaded_at TIMESTAMPTZ DEFAULT NOW()
);

-- Tabla de sesiones de estudio
CREATE TABLE IF NOT EXISTS study_sessions (
  id SERIAL PRIMARY KEY,
  user_id INT NOT NULL REFERENCES users(id) ON DELETE CASCADE ON UPDATE CASCADE,
  document_id INT NOT NULL REFERENCES documents(id) ON DELETE CASCADE ON UPDATE CASCADE,
  difficulty_level_id INT NOT NULL REFERENCES difficulty_levels(id) ON DELETE RESTRICT ON UPDATE CASCADE,
  evaluation_type_id INT NOT NULL REFERENCES evaluation_types(id) ON DELETE RESTRICT ON UPDATE CASCADE,
  title VARCHAR(255) NOT NULL,
  summary_body TEXT NOT NULL,
  created_at TIMESTAMPTZ DEFAULT NOW()
);

-- Tabla de datos del quiz
CREATE TABLE IF NOT EXISTS quizz_data (
  id SERIAL PRIMARY KEY,
  study_session_id INT NOT NULL UNIQUE REFERENCES study_sessions(id) ON DELETE CASCADE ON UPDATE CASCADE,
  quiz_data_t0 JSONB NOT NULL,
  quiz_data_t48 JSONB,
  is_frozen BOOLEAN DEFAULT FALSE,
  t0_completed_at TIMESTAMPTZ,
  t48_generated_at TIMESTAMPTZ,
  created_at TIMESTAMPTZ DEFAULT NOW()
);

-- Tabla de intentos
CREATE TABLE IF NOT EXISTS attempts (
  id SERIAL PRIMARY KEY,
  user_id INT NOT NULL REFERENCES users(id) ON DELETE CASCADE ON UPDATE CASCADE,
  study_session_id INT NOT NULL REFERENCES study_sessions(id) ON DELETE CASCADE ON UPDATE CASCADE,
  timing_tag VARCHAR(10) NOT NULL,
  user_answers JSONB NOT NULL,
  score FLOAT NOT NULL,
  max_possible_score FLOAT DEFAULT 100.0,
  ai_feedback JSONB,
  iri_value FLOAT,
  started_at TIMESTAMPTZ DEFAULT NOW(),
  completed_at TIMESTAMPTZ,
  grading_completed_at TIMESTAMPTZ,
  CONSTRAINT unique_attempt_per_timing UNIQUE (study_session_id, timing_tag),
  CONSTRAINT chk_attempts_timing_tag CHECK (timing_tag IN ('T0', 'T48')),
  CONSTRAINT chk_attempts_score CHECK (score >= 0 AND score <= 100),
  CONSTRAINT chk_attempts_iri_value CHECK (iri_value IS NULL OR (iri_value >= 0 AND iri_value <= 100))
);

-- Tabla de recordatorios programados
CREATE TABLE IF NOT EXISTS scheduled_reminders (
  id SERIAL PRIMARY KEY,
  user_id INT NOT NULL REFERENCES users(id) ON DELETE CASCADE ON UPDATE CASCADE,
  study_session_id INT NOT NULL REFERENCES study_sessions(id) ON DELETE CASCADE ON UPDATE CASCADE,
  timing_tag VARCHAR(10) DEFAULT 'T48',
  scheduled_for TIMESTAMPTZ NOT NULL,
  status VARCHAR(20) DEFAULT 'pending',
  sent_at TIMESTAMPTZ,
  error_message TEXT,
  notification_payload JSONB,
  created_at TIMESTAMPTZ DEFAULT NOW(),
  CONSTRAINT chk_reminders_status CHECK (status IN ('pending', 'sent', 'failed')),
  CONSTRAINT chk_reminders_timing_tag CHECK (timing_tag IN ('T48'))
);

-- Tabla de streaks de usuario
CREATE TABLE IF NOT EXISTS user_streaks (
  id SERIAL PRIMARY KEY,
  user_id INT NOT NULL UNIQUE REFERENCES users(id) ON DELETE CASCADE ON UPDATE CASCADE,
  current_streak INT DEFAULT 0,
  best_streak INT DEFAULT 0,
  last_activity_date TIMESTAMPTZ,
  average_iri FLOAT DEFAULT 0,
  best_iri FLOAT DEFAULT 0,
  total_sessions INT DEFAULT 0,
  total_t48_completed INT DEFAULT 0,
  updated_at TIMESTAMPTZ DEFAULT NOW(),
  CONSTRAINT chk_streaks_current_streak CHECK (current_streak >= 0),
  CONSTRAINT chk_streaks_best_streak CHECK (best_streak >= 0),
  CONSTRAINT chk_streaks_average_iri CHECK (average_iri >= 0 AND average_iri <= 100)
);

-- Tabla de refresh tokens
CREATE TABLE IF NOT EXISTS refresh_tokens (
  id SERIAL PRIMARY KEY,
  token VARCHAR(512) NOT NULL UNIQUE,
  user_id INT NOT NULL REFERENCES users(id) ON DELETE CASCADE ON UPDATE CASCADE,
  expires_at TIMESTAMPTZ NOT NULL,
  created_at TIMESTAMPTZ DEFAULT NOW(),
  revoked_at TIMESTAMPTZ
);

-- Tabla de reportes de retención (generada por sp_generate_retention_report)
CREATE TABLE IF NOT EXISTS retention_reports (
  id SERIAL PRIMARY KEY,
  generated_at TIMESTAMPTZ DEFAULT NOW(),
  user_id INT NOT NULL REFERENCES users(id) ON DELETE CASCADE ON UPDATE CASCADE,
  username VARCHAR,
  total_sessions INT,
  completed_sessions INT,
  completion_rate NUMERIC,
  avg_iri NUMERIC,
  best_iri NUMERIC,
  avg_improvement NUMERIC
);

-- ============================================================
-- ÍNDICES
-- ============================================================

CREATE INDEX IF NOT EXISTS idx_documents_user_id ON documents(user_id);
CREATE INDEX IF NOT EXISTS idx_documents_hash ON documents(document_hash);
CREATE INDEX IF NOT EXISTS idx_study_sessions_user_id ON study_sessions(user_id);
CREATE INDEX IF NOT EXISTS idx_study_sessions_document_id ON study_sessions(document_id);
CREATE INDEX IF NOT EXISTS idx_attempts_user_id ON attempts(user_id);
CREATE INDEX IF NOT EXISTS idx_attempts_study_session_id ON attempts(study_session_id);
CREATE INDEX IF NOT EXISTS idx_refresh_tokens_user_id ON refresh_tokens(user_id);
CREATE INDEX IF NOT EXISTS idx_refresh_tokens_token ON refresh_tokens(token);

-- ============================================================
-- FUNCIONES
-- ============================================================

-- FUNCIÓN 1: ESCALAR — fn_get_session_status
-- Retorna el status de una sesión: 'pending' | 't0_completed' | 'completed'
-- Uso: SELECT fn_get_session_status(7);
--      SELECT id, title, fn_get_session_status(id) AS status FROM study_sessions;

CREATE OR REPLACE FUNCTION fn_get_session_status(p_session_id INT)
RETURNS VARCHAR AS $$
DECLARE
  v_has_t0  BOOLEAN := FALSE;
  v_has_t48 BOOLEAN := FALSE;
BEGIN
  SELECT EXISTS (
    SELECT 1 FROM attempts
    WHERE study_session_id = p_session_id
      AND timing_tag = 'T0'
      AND completed_at IS NOT NULL
  ) INTO v_has_t0;

  SELECT EXISTS (
    SELECT 1 FROM attempts
    WHERE study_session_id = p_session_id
      AND timing_tag = 'T48'
      AND completed_at IS NOT NULL
  ) INTO v_has_t48;

  IF v_has_t0 AND v_has_t48 THEN
    RETURN 'completed';
  ELSIF v_has_t0 THEN
    RETURN 't0_completed';
  ELSE
    RETURN 'pending';
  END IF;
END;
$$ LANGUAGE plpgsql STABLE;


-- FUNCIÓN 2: TABULAR — fn_get_user_retention_detail
-- Retorna el detalle de retención por sesión de un usuario
-- Uso: SELECT * FROM fn_get_user_retention_detail(4);
--      SELECT * FROM fn_get_user_retention_detail(4) WHERE status = 'completed';

CREATE OR REPLACE FUNCTION fn_get_user_retention_detail(p_user_id INT)
RETURNS TABLE (
  session_id        INT,
  title             VARCHAR,
  difficulty_level  VARCHAR,
  evaluation_type   VARCHAR,
  status            VARCHAR,
  score_t0          FLOAT,
  score_t48         FLOAT,
  iri               FLOAT,
  score_improvement NUMERIC,
  created_at        TIMESTAMPTZ,
  completed_at      TIMESTAMPTZ
) AS $$
BEGIN
  RETURN QUERY
  SELECT
    ss.id                                          AS session_id,
    ss.title,
    dl.display_name                                AS difficulty_level,
    et.display_name                                AS evaluation_type,
    fn_get_session_status(ss.id)                   AS status,
    a_t0.score                                     AS score_t0,
    a_t48.score                                    AS score_t48,
    a_t48.iri_value                                AS iri,
    ROUND((a_t48.score - a_t0.score)::numeric, 1)  AS score_improvement,
    ss.created_at,
    a_t48.completed_at                             AS completed_at
  FROM study_sessions ss
  JOIN difficulty_levels dl ON ss.difficulty_level_id = dl.id
  JOIN evaluation_types et  ON ss.evaluation_type_id  = et.id
  LEFT JOIN attempts a_t0  ON ss.id = a_t0.study_session_id
    AND a_t0.timing_tag = 'T0'
    AND a_t0.completed_at IS NOT NULL
  LEFT JOIN attempts a_t48 ON ss.id = a_t48.study_session_id
    AND a_t48.timing_tag = 'T48'
    AND a_t48.completed_at IS NOT NULL
  WHERE ss.user_id = p_user_id
  ORDER BY ss.created_at DESC;
END;
$$ LANGUAGE plpgsql STABLE;

