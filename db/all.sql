-- ============================================================
-- MTG Bartender — Combined Schema + RLS Policies
-- ============================================================
-- This file combines schema.sql and supabase_policies.sql.
-- Run the entire file in one go from the Supabase SQL editor
-- (Dashboard > SQL Editor > New query > paste > Run).
--
-- To apply incrementally (recommended for existing projects):
--   1. Run schema.sql first
--   2. Run supabase_policies.sql second
-- ============================================================


-- ============================================================
-- PART 1: SCHEMA
-- ============================================================


-- ------------------------------------------------------------
-- Extensions
-- ------------------------------------------------------------

CREATE EXTENSION IF NOT EXISTS "pgcrypto";
CREATE EXTENSION IF NOT EXISTS "pg_trgm";


-- ------------------------------------------------------------
-- Enums
-- ------------------------------------------------------------

CREATE TYPE game_system AS ENUM (
  'mtg', 'pokemon', 'lorcana', 'flesh_and_blood', 'yugioh', 'other'
);

CREATE TYPE tournament_format AS ENUM (
  'standard', 'pioneer', 'modern', 'legacy', 'vintage', 'pauper',
  'commander', 'draft', 'sealed', 'jumpstart', 'two_headed_giant', 'other'
);

CREATE TYPE pairing_system AS ENUM (
  'swiss', 'single_elimination', 'double_elimination', 'round_robin'
);

CREATE TYPE tournament_status AS ENUM (
  'scheduled', 'registration_open', 'registration_closed',
  'in_progress', 'top_cut', 'completed', 'cancelled'
);

CREATE TYPE event_status AS ENUM (
  'draft', 'published', 'cancelled', 'completed'
);

CREATE TYPE round_status AS ENUM (
  'pending', 'active', 'completed'
);

CREATE TYPE match_status AS ENUM (
  'pending', 'in_progress', 'completed', 'bye'
);

CREATE TYPE match_result AS ENUM (
  'player_a_wins', 'player_b_wins', 'draw'
);

CREATE TYPE registration_status AS ENUM (
  'registered', 'checked_in', 'dropped', 'disqualified'
);

CREATE TYPE store_role AS ENUM (
  'owner', 'judge', 'staff'
);


-- ------------------------------------------------------------
-- Profiles
-- ------------------------------------------------------------

CREATE TABLE profiles (
  id           uuid        PRIMARY KEY REFERENCES auth.users(id) ON DELETE CASCADE,
  handle       text        UNIQUE NOT NULL,
  full_name    text,
  avatar_url   text,
  city         text,
  country      text        NOT NULL DEFAULT 'ES',
  bio          text,
  dci_number   text        UNIQUE,
  is_verified  boolean     NOT NULL DEFAULT false,
  created_at   timestamptz NOT NULL DEFAULT now(),
  updated_at   timestamptz NOT NULL DEFAULT now()
);

COMMENT ON TABLE  profiles             IS 'Public player profiles, one per auth user.';
COMMENT ON COLUMN profiles.handle     IS 'Unique public display name chosen by the player.';
COMMENT ON COLUMN profiles.dci_number IS 'Wizards of the Coast player ID (formerly DCI number).';


-- ------------------------------------------------------------
-- Stores
-- ------------------------------------------------------------

CREATE TABLE stores (
  id           uuid          PRIMARY KEY DEFAULT gen_random_uuid(),
  name         text          NOT NULL,
  slug         text          UNIQUE NOT NULL,
  description  text,
  address      text,
  city         text,
  country      text          NOT NULL DEFAULT 'ES',
  latitude     numeric(9,6),
  longitude    numeric(9,6),
  website      text,
  logo_url     text,
  contact_info jsonb,
  game_systems game_system[] NOT NULL DEFAULT '{mtg}',
  is_verified  boolean       NOT NULL DEFAULT false,
  created_at   timestamptz   NOT NULL DEFAULT now()
);

COMMENT ON TABLE stores IS 'Game stores that host and organise events.';


-- ------------------------------------------------------------
-- Store staff
-- ------------------------------------------------------------

CREATE TABLE store_staff (
  id         uuid        PRIMARY KEY DEFAULT gen_random_uuid(),
  store_id   uuid        NOT NULL REFERENCES stores(id) ON DELETE CASCADE,
  user_id    uuid        NOT NULL REFERENCES auth.users(id) ON DELETE CASCADE,
  role       store_role  NOT NULL DEFAULT 'staff',
  created_at timestamptz NOT NULL DEFAULT now(),
  UNIQUE (store_id, user_id)
);

COMMENT ON TABLE store_staff IS 'Per-store roles. A user can have different roles at different stores.';


-- ------------------------------------------------------------
-- Venues
-- ------------------------------------------------------------

CREATE TABLE venues (
  id         uuid        PRIMARY KEY DEFAULT gen_random_uuid(),
  store_id   uuid        NOT NULL REFERENCES stores(id) ON DELETE CASCADE,
  name       text        NOT NULL,
  capacity   int         NOT NULL DEFAULT 20,
  details    jsonb,
  created_at timestamptz NOT NULL DEFAULT now()
);

COMMENT ON TABLE venues IS 'Physical spaces within a store where events can be held.';


-- ------------------------------------------------------------
-- Events
-- ------------------------------------------------------------

CREATE TABLE events (
  id                     uuid         PRIMARY KEY DEFAULT gen_random_uuid(),
  store_id               uuid         REFERENCES stores(id) ON DELETE SET NULL,
  venue_id               uuid         REFERENCES venues(id) ON DELETE SET NULL,
  created_by             uuid         REFERENCES auth.users(id) ON DELETE SET NULL,
  title                  text         NOT NULL,
  description            text,
  banner_image_url       text,
  game_system            game_system  NOT NULL DEFAULT 'mtg',
  status                 event_status NOT NULL DEFAULT 'draft',
  start_datetime         timestamptz  NOT NULL,
  end_datetime           timestamptz,
  registration_opens_at  timestamptz,
  registration_closes_at timestamptz,
  entry_fee              numeric(8,2) NOT NULL DEFAULT 0,
  capacity               int          NOT NULL DEFAULT 100,
  is_public              boolean      NOT NULL DEFAULT true,
  metadata               jsonb,
  created_at             timestamptz  NOT NULL DEFAULT now()
);

COMMENT ON TABLE events IS 'A scheduled event at a store. Parent of tournaments.';


-- ------------------------------------------------------------
-- Tournaments
-- ------------------------------------------------------------

CREATE TABLE tournaments (
  id             uuid              PRIMARY KEY DEFAULT gen_random_uuid(),
  event_id       uuid              NOT NULL REFERENCES events(id) ON DELETE CASCADE,
  judge_id       uuid              REFERENCES auth.users(id) ON DELETE SET NULL,
  title          text              NOT NULL,
  format         tournament_format NOT NULL DEFAULT 'standard',
  pairing_system pairing_system    NOT NULL DEFAULT 'swiss',
  status         tournament_status NOT NULL DEFAULT 'scheduled',
  min_players    int               NOT NULL DEFAULT 4,
  max_players    int               NOT NULL DEFAULT 64,
  total_rounds   int,
  current_round  int               NOT NULL DEFAULT 0,
  top_cut        int               NOT NULL DEFAULT 8,
  entry_fee      numeric(8,2)      NOT NULL DEFAULT 0,
  prize_pool     jsonb,
  rules          jsonb,
  created_at     timestamptz       NOT NULL DEFAULT now()
);

COMMENT ON TABLE  tournaments              IS 'A competitive bracket within an event.';
COMMENT ON COLUMN tournaments.total_rounds IS 'If NULL, auto-calculated: ceil(log2(player_count)) for swiss.';
COMMENT ON COLUMN tournaments.top_cut      IS '0 = no top cut. 8 = top 8 advance to single elimination.';


-- ------------------------------------------------------------
-- Registrations
-- ------------------------------------------------------------

CREATE TABLE registrations (
  id              uuid                PRIMARY KEY DEFAULT gen_random_uuid(),
  tournament_id   uuid                NOT NULL REFERENCES tournaments(id) ON DELETE CASCADE,
  user_id         uuid                NOT NULL REFERENCES auth.users(id) ON DELETE CASCADE,
  status          registration_status NOT NULL DEFAULT 'registered',
  seed            int,
  final_standing  int,
  paid            boolean             NOT NULL DEFAULT false,
  notes           text,
  created_at      timestamptz         NOT NULL DEFAULT now(),
  UNIQUE (tournament_id, user_id)
);

COMMENT ON TABLE registrations IS 'A player entry in a tournament.';


-- ------------------------------------------------------------
-- Deck submissions
-- ------------------------------------------------------------

CREATE TABLE deck_submissions (
  id            uuid        PRIMARY KEY DEFAULT gen_random_uuid(),
  tournament_id uuid        NOT NULL REFERENCES tournaments(id) ON DELETE CASCADE,
  user_id       uuid        NOT NULL REFERENCES auth.users(id) ON DELETE CASCADE,
  deck_name     text,
  main_deck     jsonb       NOT NULL DEFAULT '[]',
  sideboard     jsonb       NOT NULL DEFAULT '[]',
  commanders    jsonb       NOT NULL DEFAULT '[]',
  submitted_at  timestamptz NOT NULL DEFAULT now(),
  updated_at    timestamptz NOT NULL DEFAULT now(),
  UNIQUE (tournament_id, user_id)
);

COMMENT ON TABLE  deck_submissions           IS 'Player deck lists submitted before a tournament.';
COMMENT ON COLUMN deck_submissions.main_deck IS 'Array of { card_name, quantity, set_code }.';


-- ------------------------------------------------------------
-- Tournament rounds
-- ------------------------------------------------------------

CREATE TABLE tournament_rounds (
  id            uuid         PRIMARY KEY DEFAULT gen_random_uuid(),
  tournament_id uuid         NOT NULL REFERENCES tournaments(id) ON DELETE CASCADE,
  round_number  int          NOT NULL,
  is_top_cut    boolean      NOT NULL DEFAULT false,
  status        round_status NOT NULL DEFAULT 'pending',
  started_at    timestamptz,
  ended_at      timestamptz,
  created_at    timestamptz  NOT NULL DEFAULT now(),
  UNIQUE (tournament_id, round_number)
);

COMMENT ON TABLE tournament_rounds IS 'Lifecycle tracking for each round in a tournament.';


-- ------------------------------------------------------------
-- Matches
-- ------------------------------------------------------------

CREATE TABLE matches (
  id            uuid         PRIMARY KEY DEFAULT gen_random_uuid(),
  tournament_id uuid         NOT NULL REFERENCES tournaments(id) ON DELETE CASCADE,
  round_id      uuid         REFERENCES tournament_rounds(id) ON DELETE SET NULL,
  round_number  int          NOT NULL,
  table_number  int,
  player_a      uuid         NOT NULL REFERENCES auth.users(id),
  player_b      uuid         REFERENCES auth.users(id),
  games_won_a   int          NOT NULL DEFAULT 0,
  games_won_b   int          NOT NULL DEFAULT 0,
  games_drawn   int          NOT NULL DEFAULT 0,
  result        match_result,
  status        match_status NOT NULL DEFAULT 'pending',
  is_bye        boolean      GENERATED ALWAYS AS (player_b IS NULL) STORED,
  reported_by   uuid         REFERENCES auth.users(id),
  confirmed_by  uuid         REFERENCES auth.users(id),
  notes         text,
  created_at    timestamptz  NOT NULL DEFAULT now()
);

COMMENT ON TABLE  matches          IS 'A pairing between two players (or a bye) in a round.';
COMMENT ON COLUMN matches.player_b IS 'NULL indicates a bye for player_a.';
COMMENT ON COLUMN matches.is_bye   IS 'Computed column: true when player_b is NULL.';


-- ------------------------------------------------------------
-- Standings
-- ------------------------------------------------------------

CREATE TABLE standings (
  id            uuid         PRIMARY KEY DEFAULT gen_random_uuid(),
  tournament_id uuid         NOT NULL REFERENCES tournaments(id) ON DELETE CASCADE,
  user_id       uuid         NOT NULL REFERENCES auth.users(id) ON DELETE CASCADE,
  after_round   int          NOT NULL,
  rank          int          NOT NULL,
  points        int          NOT NULL DEFAULT 0,
  match_wins    int          NOT NULL DEFAULT 0,
  match_losses  int          NOT NULL DEFAULT 0,
  match_draws   int          NOT NULL DEFAULT 0,
  game_wins     int          NOT NULL DEFAULT 0,
  game_losses   int          NOT NULL DEFAULT 0,
  game_draws    int          NOT NULL DEFAULT 0,
  omw_pct       numeric(5,4) NOT NULL DEFAULT 0,
  ogw_pct       numeric(5,4) NOT NULL DEFAULT 0,
  pgw_pct       numeric(5,4) NOT NULL DEFAULT 0,
  created_at    timestamptz  NOT NULL DEFAULT now(),
  UNIQUE (tournament_id, user_id, after_round)
);

COMMENT ON TABLE  standings         IS 'Standings snapshot after each round, written by the tournament engine.';
COMMENT ON COLUMN standings.omw_pct IS 'Opponent match-win % — MTG tiebreaker 1. Standard floor is 0.3300.';
COMMENT ON COLUMN standings.ogw_pct IS 'Opponent game-win % — MTG tiebreaker 2. Standard floor is 0.3300.';
COMMENT ON COLUMN standings.pgw_pct IS 'Player game-win % — MTG tiebreaker 3. Standard floor is 0.3300.';


-- ------------------------------------------------------------
-- Player ratings
-- ------------------------------------------------------------

CREATE TABLE player_ratings (
  id           uuid              PRIMARY KEY DEFAULT gen_random_uuid(),
  user_id      uuid              NOT NULL REFERENCES auth.users(id) ON DELETE CASCADE,
  game_system  game_system       NOT NULL DEFAULT 'mtg',
  format       tournament_format,
  rating       int               NOT NULL DEFAULT 1200,
  peak_rating  int               NOT NULL DEFAULT 1200,
  games_played int               NOT NULL DEFAULT 0,
  updated_at   timestamptz       NOT NULL DEFAULT now(),
  UNIQUE (user_id, game_system, format)
);

COMMENT ON TABLE  player_ratings        IS 'ELO-style rating per player per game system and format.';
COMMENT ON COLUMN player_ratings.rating IS 'Starting ELO is 1200.';
COMMENT ON COLUMN player_ratings.format IS 'NULL = overall rating across all formats for that game system.';


-- ------------------------------------------------------------
-- Indexes
-- ------------------------------------------------------------

CREATE INDEX idx_profiles_city         ON profiles (city);
CREATE INDEX idx_profiles_handle_trgm  ON profiles USING gin (handle gin_trgm_ops);
CREATE INDEX idx_stores_city           ON stores (city);
CREATE INDEX idx_stores_slug           ON stores (slug);
CREATE INDEX idx_stores_location       ON stores (latitude, longitude);
CREATE INDEX idx_stores_name_trgm      ON stores USING gin (name gin_trgm_ops);
CREATE INDEX idx_store_staff_store     ON store_staff (store_id);
CREATE INDEX idx_store_staff_user      ON store_staff (user_id);
CREATE INDEX idx_events_store          ON events (store_id);
CREATE INDEX idx_events_start          ON events (start_datetime);
CREATE INDEX idx_events_status         ON events (status);
CREATE INDEX idx_events_game_system    ON events (game_system);
CREATE INDEX idx_tournaments_event     ON tournaments (event_id);
CREATE INDEX idx_tournaments_status    ON tournaments (status);
CREATE INDEX idx_tournaments_format    ON tournaments (format);
CREATE INDEX idx_reg_tournament        ON registrations (tournament_id);
CREATE INDEX idx_reg_user              ON registrations (user_id);
CREATE INDEX idx_reg_status            ON registrations (status);
CREATE INDEX idx_rounds_tournament     ON tournament_rounds (tournament_id);
CREATE INDEX idx_rounds_status         ON tournament_rounds (status);
CREATE INDEX idx_matches_tournament    ON matches (tournament_id);
CREATE INDEX idx_matches_round         ON matches (tournament_id, round_number);
CREATE INDEX idx_matches_player_a      ON matches (player_a);
CREATE INDEX idx_matches_player_b      ON matches (player_b);
CREATE INDEX idx_matches_status        ON matches (status);
CREATE INDEX idx_standings_tournament  ON standings (tournament_id);
CREATE INDEX idx_standings_user        ON standings (user_id);
CREATE INDEX idx_standings_round_rank  ON standings (tournament_id, after_round, rank);
CREATE INDEX idx_ratings_user          ON player_ratings (user_id);
CREATE INDEX idx_ratings_format        ON player_ratings (game_system, format);
CREATE INDEX idx_ratings_top           ON player_ratings (rating DESC);
CREATE INDEX idx_decks_tournament      ON deck_submissions (tournament_id);
CREATE INDEX idx_decks_user            ON deck_submissions (user_id);


-- ------------------------------------------------------------
-- Triggers
-- ------------------------------------------------------------

-- Auto-create a profile row when a new user signs up.
CREATE OR REPLACE FUNCTION handle_new_user()
RETURNS trigger
LANGUAGE plpgsql
SECURITY DEFINER SET search_path = public
AS $$
BEGIN
  INSERT INTO public.profiles (id, handle, full_name, avatar_url)
  VALUES (
    NEW.id,
    'player_' || substring(NEW.id::text, 1, 8),
    NEW.raw_user_meta_data->>'full_name',
    NEW.raw_user_meta_data->>'avatar_url'
  );
  RETURN NEW;
END;
$$;

CREATE TRIGGER on_auth_user_created
  AFTER INSERT ON auth.users
  FOR EACH ROW EXECUTE FUNCTION handle_new_user();

-- Auto-update updated_at timestamps.
CREATE OR REPLACE FUNCTION set_updated_at()
RETURNS trigger
LANGUAGE plpgsql
AS $$
BEGIN
  NEW.updated_at = now();
  RETURN NEW;
END;
$$;

CREATE TRIGGER set_profiles_updated_at
  BEFORE UPDATE ON profiles
  FOR EACH ROW EXECUTE FUNCTION set_updated_at();

CREATE TRIGGER set_deck_submissions_updated_at
  BEFORE UPDATE ON deck_submissions
  FOR EACH ROW EXECUTE FUNCTION set_updated_at();


-- ============================================================
-- PART 2: RLS POLICIES
-- ============================================================


-- ------------------------------------------------------------
-- Helper functions
-- ------------------------------------------------------------

CREATE OR REPLACE FUNCTION is_store_staff(p_store_id uuid)
RETURNS boolean
LANGUAGE sql
SECURITY DEFINER SET search_path = public
STABLE
AS $$
  SELECT EXISTS (
    SELECT 1 FROM store_staff
    WHERE store_id = p_store_id AND user_id = auth.uid()
  );
$$;

CREATE OR REPLACE FUNCTION is_store_owner(p_store_id uuid)
RETURNS boolean
LANGUAGE sql
SECURITY DEFINER SET search_path = public
STABLE
AS $$
  SELECT EXISTS (
    SELECT 1 FROM store_staff
    WHERE store_id = p_store_id AND user_id = auth.uid() AND role = 'owner'
  );
$$;

CREATE OR REPLACE FUNCTION is_tournament_judge(p_tournament_id uuid)
RETURNS boolean
LANGUAGE sql
SECURITY DEFINER SET search_path = public
STABLE
AS $$
  SELECT EXISTS (
    SELECT 1 FROM tournaments
    WHERE id = p_tournament_id AND judge_id = auth.uid()
  );
$$;

CREATE OR REPLACE FUNCTION tournament_store_id(p_tournament_id uuid)
RETURNS uuid
LANGUAGE sql
SECURITY DEFINER SET search_path = public
STABLE
AS $$
  SELECT e.store_id
  FROM tournaments t
  JOIN events e ON e.id = t.event_id
  WHERE t.id = p_tournament_id;
$$;


-- ------------------------------------------------------------
-- Profiles
-- ------------------------------------------------------------

ALTER TABLE profiles ENABLE ROW LEVEL SECURITY;

CREATE POLICY profiles_select_public ON profiles FOR SELECT USING (true);

CREATE POLICY profiles_update_own ON profiles FOR UPDATE
  USING (auth.uid() = id) WITH CHECK (auth.uid() = id);


-- ------------------------------------------------------------
-- Stores
-- ------------------------------------------------------------

ALTER TABLE stores ENABLE ROW LEVEL SECURITY;

CREATE POLICY stores_select_public ON stores FOR SELECT
  USING (is_verified = true);

CREATE POLICY stores_select_own_staff ON stores FOR SELECT
  USING (is_store_staff(id));

CREATE POLICY stores_insert_authenticated ON stores FOR INSERT
  WITH CHECK (auth.role() = 'authenticated');

CREATE POLICY stores_update_owner ON stores FOR UPDATE
  USING (is_store_owner(id)) WITH CHECK (is_store_owner(id));

CREATE POLICY stores_delete_owner ON stores FOR DELETE
  USING (is_store_owner(id));


-- ------------------------------------------------------------
-- Store staff
-- ------------------------------------------------------------

ALTER TABLE store_staff ENABLE ROW LEVEL SECURITY;

CREATE POLICY store_staff_select ON store_staff FOR SELECT
  USING (is_store_staff(store_id));

CREATE POLICY store_staff_insert_owner ON store_staff FOR INSERT
  WITH CHECK (is_store_owner(store_id));

CREATE POLICY store_staff_update_owner ON store_staff FOR UPDATE
  USING (is_store_owner(store_id)) WITH CHECK (is_store_owner(store_id));

CREATE POLICY store_staff_delete_owner ON store_staff FOR DELETE
  USING (is_store_owner(store_id));


-- ------------------------------------------------------------
-- Venues
-- ------------------------------------------------------------

ALTER TABLE venues ENABLE ROW LEVEL SECURITY;

CREATE POLICY venues_select_public ON venues FOR SELECT
  USING (EXISTS (SELECT 1 FROM stores s WHERE s.id = store_id AND s.is_verified = true));

CREATE POLICY venues_select_staff ON venues FOR SELECT
  USING (is_store_staff(store_id));

CREATE POLICY venues_insert_staff ON venues FOR INSERT
  WITH CHECK (is_store_staff(store_id));

CREATE POLICY venues_update_staff ON venues FOR UPDATE
  USING (is_store_staff(store_id)) WITH CHECK (is_store_staff(store_id));

CREATE POLICY venues_delete_owner ON venues FOR DELETE
  USING (is_store_owner(store_id));


-- ------------------------------------------------------------
-- Events
-- ------------------------------------------------------------

ALTER TABLE events ENABLE ROW LEVEL SECURITY;

CREATE POLICY events_select_public ON events FOR SELECT
  USING (is_public = true AND status = 'published');

CREATE POLICY events_select_staff ON events FOR SELECT
  USING (is_store_staff(store_id));

CREATE POLICY events_insert_staff ON events FOR INSERT
  WITH CHECK (is_store_staff(store_id));

CREATE POLICY events_update_staff ON events FOR UPDATE
  USING (is_store_staff(store_id)) WITH CHECK (is_store_staff(store_id));

CREATE POLICY events_delete_owner ON events FOR DELETE
  USING (is_store_owner(store_id));


-- ------------------------------------------------------------
-- Tournaments
-- ------------------------------------------------------------

ALTER TABLE tournaments ENABLE ROW LEVEL SECURITY;

CREATE POLICY tournaments_select_public ON tournaments FOR SELECT
  USING (
    EXISTS (
      SELECT 1 FROM events e
      WHERE e.id = event_id AND e.is_public = true AND e.status = 'published'
    )
  );

CREATE POLICY tournaments_select_staff ON tournaments FOR SELECT
  USING (
    judge_id = auth.uid()
    OR EXISTS (SELECT 1 FROM events e WHERE e.id = event_id AND is_store_staff(e.store_id))
  );

CREATE POLICY tournaments_insert_staff ON tournaments FOR INSERT
  WITH CHECK (
    EXISTS (SELECT 1 FROM events e WHERE e.id = event_id AND is_store_staff(e.store_id))
  );

CREATE POLICY tournaments_update_staff_or_judge ON tournaments FOR UPDATE
  USING (
    judge_id = auth.uid()
    OR EXISTS (SELECT 1 FROM events e WHERE e.id = event_id AND is_store_staff(e.store_id))
  )
  WITH CHECK (
    judge_id = auth.uid()
    OR EXISTS (SELECT 1 FROM events e WHERE e.id = event_id AND is_store_staff(e.store_id))
  );

CREATE POLICY tournaments_delete_owner ON tournaments FOR DELETE
  USING (
    EXISTS (SELECT 1 FROM events e WHERE e.id = event_id AND is_store_owner(e.store_id))
  );


-- ------------------------------------------------------------
-- Registrations
-- ------------------------------------------------------------

ALTER TABLE registrations ENABLE ROW LEVEL SECURITY;

CREATE POLICY registrations_select_own ON registrations FOR SELECT
  USING (auth.uid() = user_id);

CREATE POLICY registrations_select_staff ON registrations FOR SELECT
  USING (
    is_tournament_judge(tournament_id)
    OR is_store_staff(tournament_store_id(tournament_id))
  );

CREATE POLICY registrations_insert_own ON registrations FOR INSERT
  WITH CHECK (auth.uid() = user_id);

CREATE POLICY registrations_update_own_or_staff ON registrations FOR UPDATE
  USING (
    auth.uid() = user_id
    OR is_tournament_judge(tournament_id)
    OR is_store_staff(tournament_store_id(tournament_id))
  )
  WITH CHECK (
    auth.uid() = user_id
    OR is_tournament_judge(tournament_id)
    OR is_store_staff(tournament_store_id(tournament_id))
  );

CREATE POLICY registrations_delete_own ON registrations FOR DELETE
  USING (
    auth.uid() = user_id
    AND EXISTS (
      SELECT 1 FROM tournaments t
      WHERE t.id = tournament_id AND t.status IN ('scheduled', 'registration_open')
    )
  );


-- ------------------------------------------------------------
-- Deck submissions
-- ------------------------------------------------------------

ALTER TABLE deck_submissions ENABLE ROW LEVEL SECURITY;

CREATE POLICY decks_select_own ON deck_submissions FOR SELECT
  USING (auth.uid() = user_id);

CREATE POLICY decks_select_judge ON deck_submissions FOR SELECT
  USING (
    is_tournament_judge(tournament_id)
    OR is_store_staff(tournament_store_id(tournament_id))
  );

CREATE POLICY decks_insert_own ON deck_submissions FOR INSERT
  WITH CHECK (auth.uid() = user_id);

CREATE POLICY decks_update_own ON deck_submissions FOR UPDATE
  USING (
    auth.uid() = user_id
    AND EXISTS (
      SELECT 1 FROM tournaments t
      WHERE t.id = tournament_id
        AND t.status IN ('scheduled', 'registration_open', 'registration_closed')
    )
  )
  WITH CHECK (auth.uid() = user_id);

CREATE POLICY decks_delete_own ON deck_submissions FOR DELETE
  USING (
    auth.uid() = user_id
    AND EXISTS (
      SELECT 1 FROM tournaments t
      WHERE t.id = tournament_id
        AND t.status IN ('scheduled', 'registration_open', 'registration_closed')
    )
  );


-- ------------------------------------------------------------
-- Tournament rounds
-- ------------------------------------------------------------

ALTER TABLE tournament_rounds ENABLE ROW LEVEL SECURITY;

CREATE POLICY rounds_select_public ON tournament_rounds FOR SELECT
  USING (
    EXISTS (
      SELECT 1 FROM tournaments t JOIN events e ON e.id = t.event_id
      WHERE t.id = tournament_id AND e.is_public = true AND e.status = 'published'
    )
  );

CREATE POLICY rounds_select_staff ON tournament_rounds FOR SELECT
  USING (
    is_tournament_judge(tournament_id)
    OR is_store_staff(tournament_store_id(tournament_id))
  );

CREATE POLICY rounds_insert_staff ON tournament_rounds FOR INSERT
  WITH CHECK (
    is_tournament_judge(tournament_id)
    OR is_store_staff(tournament_store_id(tournament_id))
  );

CREATE POLICY rounds_update_staff ON tournament_rounds FOR UPDATE
  USING (
    is_tournament_judge(tournament_id)
    OR is_store_staff(tournament_store_id(tournament_id))
  )
  WITH CHECK (
    is_tournament_judge(tournament_id)
    OR is_store_staff(tournament_store_id(tournament_id))
  );


-- ------------------------------------------------------------
-- Matches
-- ------------------------------------------------------------

ALTER TABLE matches ENABLE ROW LEVEL SECURITY;

CREATE POLICY matches_select_players ON matches FOR SELECT
  USING (auth.uid() = player_a OR auth.uid() = player_b);

CREATE POLICY matches_select_public ON matches FOR SELECT
  USING (
    EXISTS (
      SELECT 1 FROM tournaments t JOIN events e ON e.id = t.event_id
      WHERE t.id = tournament_id AND e.is_public = true AND e.status = 'published'
    )
  );

CREATE POLICY matches_select_staff ON matches FOR SELECT
  USING (
    is_tournament_judge(tournament_id)
    OR is_store_staff(tournament_store_id(tournament_id))
  );

CREATE POLICY matches_insert_staff ON matches FOR INSERT
  WITH CHECK (
    is_tournament_judge(tournament_id)
    OR is_store_staff(tournament_store_id(tournament_id))
  );

CREATE POLICY matches_update_players_or_staff ON matches FOR UPDATE
  USING (
    auth.uid() = player_a
    OR auth.uid() = player_b
    OR is_tournament_judge(tournament_id)
    OR is_store_staff(tournament_store_id(tournament_id))
  )
  WITH CHECK (
    auth.uid() = player_a
    OR auth.uid() = player_b
    OR is_tournament_judge(tournament_id)
    OR is_store_staff(tournament_store_id(tournament_id))
  );


-- ------------------------------------------------------------
-- Standings (read-only for clients; written by service role)
-- ------------------------------------------------------------

ALTER TABLE standings ENABLE ROW LEVEL SECURITY;

CREATE POLICY standings_select_public ON standings FOR SELECT
  USING (
    EXISTS (
      SELECT 1 FROM tournaments t JOIN events e ON e.id = t.event_id
      WHERE t.id = tournament_id AND e.is_public = true AND e.status = 'published'
    )
  );

CREATE POLICY standings_select_own ON standings FOR SELECT
  USING (auth.uid() = user_id);


-- ------------------------------------------------------------
-- Player ratings (read-only for clients; written by service role)
-- ------------------------------------------------------------

ALTER TABLE player_ratings ENABLE ROW LEVEL SECURITY;

CREATE POLICY ratings_select_public ON player_ratings FOR SELECT USING (true);


-- ============================================================
-- END
-- ============================================================
