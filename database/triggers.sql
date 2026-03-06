-- ============================================================
-- Readflow — Triggers
-- Ejecutar en Supabase SQL Editor
-- ============================================================


-- ============================================================
-- TRIGGER 1: Crear UserStreak automáticamente al registrar usuario
-- ============================================================

CREATE OR REPLACE FUNCTION fn_create_user_streak()
RETURNS TRIGGER AS $$
BEGIN
  INSERT INTO user_streaks (user_id, current_streak, best_streak, average_iri, best_iri, total_sessions, total_t48_completed)
  VALUES (NEW.id, 0, 0, 0, 0, 0, 0);
  RETURN NEW;
END;
$$ LANGUAGE plpgsql;

CREATE OR REPLACE TRIGGER trg_create_user_streak
AFTER INSERT ON users
FOR EACH ROW
EXECUTE FUNCTION fn_create_user_streak();


-- ============================================================
-- TRIGGER 2: Actualizar updated_at automáticamente
-- Aplica a: users, user_streaks
-- ============================================================

CREATE OR REPLACE FUNCTION fn_update_timestamp()
RETURNS TRIGGER AS $$
BEGIN
  NEW.updated_at = NOW();
  RETURN NEW;
END;
$$ LANGUAGE plpgsql;

CREATE OR REPLACE TRIGGER trg_users_updated_at
BEFORE UPDATE ON users
FOR EACH ROW
EXECUTE FUNCTION fn_update_timestamp();

CREATE OR REPLACE TRIGGER trg_user_streaks_updated_at
BEFORE UPDATE ON user_streaks
FOR EACH ROW
EXECUTE FUNCTION fn_update_timestamp();


-- ============================================================
-- TRIGGER 3: Actualizar streak al completar un attempt
-- Lógica:
--   - Solo actúa cuando completed_at pasa de NULL a un valor (se completa)
--   - Si el attempt es del día actual o día siguiente al último: incrementa streak
--   - Si hay un gap de más de 1 día: resetea streak a 1
--   - Siempre actualiza best_streak si el actual lo supera
--   - Actualiza last_activity_date
-- ============================================================

CREATE OR REPLACE FUNCTION fn_update_user_streak()
RETURNS TRIGGER AS $$
DECLARE
  v_last_activity DATE;
  v_current_streak INT;
  v_best_streak INT;
  v_today DATE := CURRENT_DATE;
BEGIN
  -- Solo actuar cuando completed_at pasa de NULL a un valor
  IF OLD.completed_at IS NULL AND NEW.completed_at IS NOT NULL THEN

    -- Obtener estado actual del streak
    SELECT
      current_streak,
      best_streak,
      last_activity_date::DATE
    INTO
      v_current_streak,
      v_best_streak,
      v_last_activity
    FROM user_streaks
    WHERE user_id = NEW.user_id;

    -- Calcular nuevo streak
    IF v_last_activity IS NULL THEN
      -- Primera actividad del usuario
      v_current_streak := 1;

    ELSIF v_last_activity = v_today THEN
      -- Ya completó algo hoy, el streak no cambia
      v_current_streak := v_current_streak;

    ELSIF v_last_activity = v_today - INTERVAL '1 day' THEN
      -- Actividad consecutiva — incrementar streak
      v_current_streak := v_current_streak + 1;

    ELSE
      -- Gap de más de 1 día — resetear streak
      v_current_streak := 1;
    END IF;

    -- Actualizar best_streak si el actual lo supera
    IF v_current_streak > v_best_streak THEN
      v_best_streak := v_current_streak;
    END IF;

    -- Persistir cambios en user_streaks
    UPDATE user_streaks
    SET
      current_streak    = v_current_streak,
      best_streak       = v_best_streak,
      last_activity_date = NOW()
    WHERE user_id = NEW.user_id;

  END IF;

  RETURN NEW;
END;
$$ LANGUAGE plpgsql;

CREATE OR REPLACE TRIGGER trg_update_streak_on_attempt
AFTER UPDATE ON attempts
FOR EACH ROW
EXECUTE FUNCTION fn_update_user_streak();


-- ============================================================
-- VERIFICAR QUE LOS TRIGGERS FUERON CREADOS
-- ============================================================
SELECT trigger_name, event_manipulation, event_object_table, action_timing
FROM information_schema.triggers
WHERE trigger_schema = 'public'
ORDER BY event_object_table, trigger_name;