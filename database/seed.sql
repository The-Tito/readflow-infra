-- ============================================================
-- Readflow — Datos iniciales (catálogos)
-- ============================================================

-- Niveles de dificultad
INSERT INTO difficulty_levels (id, slug, display_name, description) VALUES
(1, 'BASIC', 'Básico', 'Initial and basic level of summary'),
(2, 'INTERMEDIATE', 'Intermedio', 'Intermediate level, no technical terms.'),
(3, 'ADVANCED', 'Avanzado', 'Advanced level, with technical terms and a specific focus.')
ON CONFLICT (id) DO NOTHING;

-- Tipos de evaluación
INSERT INTO evaluation_types (id, slug, display_name) VALUES
(1, 'MULTIPLE_CHOICE', 'Opción Múltiple'),
(2, 'FILL_IN_THE_BLANKS', 'Completar Espacios (Drag and Drop)'),
(3, 'FREE_WRITING', 'Redacción libre')
ON CONFLICT (id) DO NOTHING;