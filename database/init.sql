-- ============================================================
-- Readflow — Schema inicial de la base de datos
-- Este archivo se ejecuta automáticamente al crear el contenedor
-- ============================================================

-- Extensiones
CREATE EXTENSION IF NOT EXISTS "uuid-ossp";

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

-- Tabla de documentos
CREATE TABLE IF NOT EXISTS documents (
  id SERIAL PRIMARY KEY,
  user_id INT NOT NULL REFERENCES users(id),
  document_hash VARCHAR(64) NOT NULL,
  original_filename VARCHAR(255) NOT NULL,
  uploaded_at TIMESTAMPTZ DEFAULT NOW(),
  CONSTRAINT unique_user_document UNIQUE (user_id, document_hash)
);

-- Tabla de sesiones de estudio
CREATE TABLE IF NOT EXISTS study_sessions (
  id SERIAL PRIMARY KEY,
  user_id INT NOT NULL REFERENCES users(id),
  document_id INT NOT NULL REFERENCES documents(id),
  difficulty_level_id INT NOT NULL REFERENCES difficulty_levels(id),
  evaluation_type_id INT NOT NULL REFERENCES evaluation_types(id),
  title VARCHAR(255) NOT NULL,
  summary_body TEXT NOT NULL,
  created_at TIMESTAMPTZ DEFAULT NOW()
);

-- Tabla de datos del quiz
CREATE TABLE IF NOT EXISTS quizz_data (
  id SERIAL PRIMARY KEY,
  study_session_id INT NOT NULL UNIQUE REFERENCES study_sessions(id),
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
  user_id INT NOT NULL REFERENCES users(id),
  study_session_id INT NOT NULL REFERENCES study_sessions(id),
  timing_tag VARCHAR(10) NOT NULL,
  user_answers JSONB NOT NULL,
  score FLOAT NOT NULL,
  max_possible_score FLOAT DEFAULT 100.0,
  ai_feedback JSONB,
  iri_value FLOAT,
  started_at TIMESTAMPTZ DEFAULT NOW(),
  completed_at TIMESTAMPTZ,
  grading_completed_at TIMESTAMPTZ,
  CONSTRAINT unique_attempt_per_timing UNIQUE (study_session_id, timing_tag)
);

-- Tabla de recordatorios programados
CREATE TABLE IF NOT EXISTS scheduled_reminders (
  id SERIAL PRIMARY KEY,
  user_id INT NOT NULL REFERENCES users(id),
  study_session_id INT NOT NULL REFERENCES study_sessions(id),
  timing_tag VARCHAR(10) DEFAULT 'T48',
  scheduled_for TIMESTAMPTZ NOT NULL,
  status VARCHAR(20) DEFAULT 'pending',
  sent_at TIMESTAMPTZ,
  error_message TEXT,
  notification_payload JSONB,
  created_at TIMESTAMPTZ DEFAULT NOW()
);

-- Tabla de streaks de usuario
CREATE TABLE IF NOT EXISTS user_streaks (
  id SERIAL PRIMARY KEY,
  user_id INT NOT NULL UNIQUE REFERENCES users(id),
  current_streak INT DEFAULT 0,
  best_streak INT DEFAULT 0,
  last_activity_date TIMESTAMPTZ,
  average_iri FLOAT DEFAULT 0,
  best_iri FLOAT DEFAULT 0,
  total_sessions INT DEFAULT 0,
  total_t48_completed INT DEFAULT 0,
  updated_at TIMESTAMPTZ DEFAULT NOW()
);

-- Tabla de refresh tokens
CREATE TABLE IF NOT EXISTS refresh_tokens (
  id SERIAL PRIMARY KEY,
  token VARCHAR(512) NOT NULL UNIQUE,
  user_id INT NOT NULL REFERENCES users(id),
  expires_at TIMESTAMPTZ NOT NULL,
  created_at TIMESTAMPTZ DEFAULT NOW(),
  revoked_at TIMESTAMPTZ
);

-- Índices
CREATE INDEX IF NOT EXISTS idx_documents_user_id ON documents(user_id);
CREATE INDEX IF NOT EXISTS idx_documents_hash ON documents(document_hash);
CREATE INDEX IF NOT EXISTS idx_study_sessions_user_id ON study_sessions(user_id);
CREATE INDEX IF NOT EXISTS idx_study_sessions_document_id ON study_sessions(document_id);
CREATE INDEX IF NOT EXISTS idx_attempts_user_id ON attempts(user_id);
CREATE INDEX IF NOT EXISTS idx_attempts_study_session_id ON attempts(study_session_id);
CREATE INDEX IF NOT EXISTS idx_refresh_tokens_user_id ON refresh_tokens(user_id);
CREATE INDEX IF NOT EXISTS idx_refresh_tokens_token ON refresh_tokens(token);

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