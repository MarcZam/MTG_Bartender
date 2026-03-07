-- ============================================================
-- MTG Bartender — Supabase helper functions
-- ============================================================
-- Run this in the Supabase SQL editor after all.sql.
-- These are called by the Python tournament engine via db.rpc().
-- ============================================================


-- Atomically increment games_played on player_ratings.
-- Called by the ratings router after a tournament completes.
CREATE OR REPLACE FUNCTION increment_games_played(
  p_user_id    uuid,
  p_game_system text,
  p_format      text,
  p_increment   int DEFAULT 1
)
RETURNS void
LANGUAGE plpgsql
SECURITY DEFINER SET search_path = public
AS $$
BEGIN
  UPDATE player_ratings
  SET    games_played = games_played + p_increment,
         updated_at   = now()
  WHERE  user_id     = p_user_id
    AND  game_system = p_game_system::game_system
    AND  format      = p_format::tournament_format;
END;
$$;

COMMENT ON FUNCTION increment_games_played IS
  'Atomically increments games_played for a player rating row. Called by the tournament engine.';
