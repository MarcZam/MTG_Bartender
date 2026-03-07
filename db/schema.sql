-- ============================================================
-- MTG Bartender — Full Database Schema v2.0
-- ============================================================
-- Run this in your Supabase SQL editor (Dashboard > SQL Editor).
-- Tables are defined in dependency order.
-- ============================================================


-- ============================================================
-- EXTENSIONS
-- ============================================================

CREATE EXTENSION IF NOT EXISTS "pgcrypto";
CREATE EXTENSION IF NOT EXISTS "pg_trgm";   -- fuzzy text search on names


-- ============================================================
-- ENUMS
-- ============================================================

-- Game systems (MTG is primary; others allow future expansion)
CREATE TYPE game_system AS ENUM (
  'mtg',
  'pokemon',
  'lorcana',
  'flesh_and_blood',
  'yugioh',
  'other'
);

-- MTG tournament formats
CREATE TYPE tournament_format AS ENUM (
  'standard',
  'pioneer',
  'modern',
  'legacy',
  'vintage',
  'pauper',
  'commander',
  'draft',
  'sealed',
  'jumpstart',
  'two_headed_giant',
  'other'
);

-- How pairings are generated each round
CREATE TYPE pairing_system AS ENUM (
  'swiss',
  'single_elimination',
  'double_elimination',
  'round_robin'
);

-- Lifecycle of a tournament
CREATE TYPE tournament_status AS ENUM (
  'scheduled',          -- created, not yet open
  'registration_open',  -- players can sign up
  'registration_closed',-- sign-up period ended, pairings not yet generated
  'in_progress',        -- rounds are being played
  'top_cut',            -- swiss finished, playoff bracket is live
  'completed',          -- final result recorded
  'cancelled'
);

-- Lifecycle of an event (the parent of tournaments)
CREATE TYPE event_status AS ENUM (
  'draft',              -- visible only to store staff
  'published',          -- publicly visible
  'cancelled',
  'completed'
);

-- Status of a single round
CREATE TYPE round_status AS ENUM (
  'pending',            -- not yet started
  'active',             -- pairings generated, matches in progress
  'completed'           -- all matches reported
);

-- Status of a single match
CREATE TYPE match_status AS ENUM (
  'pending',            -- waiting to be played
  'in_progress',        -- players seated
  'completed',          -- result submitted
  'bye'                 -- automatic win (odd player count)
);

-- Who won a match
CREATE TYPE match_result AS ENUM (
  'player_a_wins',
  'player_b_wins',
  'draw'
);

-- A player's status within a tournament
CREATE TYPE registration_status AS ENUM (
  'registered',         -- signed up, not yet checked in
  'checked_in',         -- confirmed present on the day
  'dropped',            -- voluntarily left mid-tournament
  'disqualified'        -- removed by judge
);

-- Roles a user can hold at a specific store
CREATE TYPE store_role AS ENUM (
  'owner',              -- full control over store and its events
  'judge',              -- can manage matches and results
  'staff'               -- can create events and check in players
);


-- ============================================================
-- PROFILES
-- One row per auth.users entry. Created automatically via trigger.
-- ============================================================

CREATE TABLE profiles (
  id           uuid        PRIMARY KEY REFERENCES auth.users(id) ON DELETE CASCADE,
  handle       text        UNIQUE NOT NULL,      -- public display name, e.g. "Rasti_42"
  full_name    text,
  avatar_url   text,
  city         text,
  country      text        NOT NULL DEFAULT 'ES',-- ISO 3166-1 alpha-2
  bio          text,
  dci_number   text        UNIQUE,               -- Wizards of the Coast player ID
  is_verified  boolean     NOT NULL DEFAULT false,
  created_at   timestamptz NOT NULL DEFAULT now(),
  updated_at   timestamptz NOT NULL DEFAULT now()
);

COMMENT ON TABLE  profiles              IS 'Public player profiles, one per auth user.';
COMMENT ON COLUMN profiles.handle      IS 'Unique public display name chosen by the player.';
COMMENT ON COLUMN profiles.dci_number  IS 'Wizards of the Coast player ID (formerly DCI number).';
COMMENT ON COLUMN profiles.is_verified IS 'Set by admins after identity check.';


-- ============================================================
-- STORES
-- A physical game store that organises events.
-- ============================================================

CREATE TABLE stores (
  id           uuid          PRIMARY KEY DEFAULT gen_random_uuid(),
  name         text          NOT NULL,
  slug         text          UNIQUE NOT NULL,    -- URL-friendly ID, e.g. "dragons-lair-madrid"
  description  text,
  address      text,
  city         text,
  country      text          NOT NULL DEFAULT 'ES',
  latitude     numeric(9,6),
  longitude    numeric(9,6),
  website      text,
  logo_url     text,
  contact_info jsonb,                            -- { phone, email, instagram, twitter, ... }
  game_systems game_system[] NOT NULL DEFAULT '{mtg}',
  is_verified  boolean       NOT NULL DEFAULT false,
  created_at   timestamptz   NOT NULL DEFAULT now()
);

COMMENT ON TABLE  stores              IS 'Game stores that host and organise events.';
COMMENT ON COLUMN stores.slug        IS 'URL-safe unique identifier for the store page.';
COMMENT ON COLUMN stores.game_systems IS 'Array of game systems this store supports.';


-- ============================================================
-- STORE STAFF
-- Maps users to roles within a specific store.
-- A user can be owner of one store and judge at another.
-- ============================================================

CREATE TABLE store_staff (
  id         uuid        PRIMARY KEY DEFAULT gen_random_uuid(),
  store_id   uuid        NOT NULL REFERENCES stores(id) ON DELETE CASCADE,
  user_id    uuid        NOT NULL REFERENCES auth.users(id) ON DELETE CASCADE,
  role       store_role  NOT NULL DEFAULT 'staff',
  created_at timestamptz NOT NULL DEFAULT now(),
  UNIQUE (store_id, user_id)
);

COMMENT ON TABLE store_staff IS 'Per-store roles. A user can have different roles at different stores.';


-- ============================================================
-- VENUES
-- A physical space inside a store where events are held.
-- ============================================================

CREATE TABLE venues (
  id         uuid        PRIMARY KEY DEFAULT gen_random_uuid(),
  store_id   uuid        NOT NULL REFERENCES stores(id) ON DELETE CASCADE,
  name       text        NOT NULL,
  capacity   int         NOT NULL DEFAULT 20,
  details    jsonb,                             -- { tables, chairs, projector, streaming_setup, ... }
  created_at timestamptz NOT NULL DEFAULT now()
);

COMMENT ON TABLE venues IS 'Physical spaces within a store where events can be held.';


-- ============================================================
-- EVENTS
-- A scheduled happening at a store (e.g. "Friday Night Magic").
-- An event is the parent container; it holds one or more tournaments.
-- ============================================================

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
  metadata               jsonb,                -- flexible extra data
  created_at             timestamptz  NOT NULL DEFAULT now()
);

COMMENT ON TABLE  events                        IS 'A scheduled event at a store. Parent of tournaments.';
COMMENT ON COLUMN events.is_public              IS 'Controls visibility on public listings.';
COMMENT ON COLUMN events.registration_opens_at  IS 'When players can start signing up. NULL = open immediately on publish.';


-- ============================================================
-- TOURNAMENTS
-- A competitive bracket within an event.
-- ============================================================

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
  total_rounds   int,                           -- NULL = auto-calc from player count
  current_round  int               NOT NULL DEFAULT 0,
  top_cut        int               NOT NULL DEFAULT 8, -- 0 = no top cut
  entry_fee      numeric(8,2)      NOT NULL DEFAULT 0,
  prize_pool     jsonb,                         -- { "1st": "...", "2nd": "...", store_credit: 50 }
  rules          jsonb,                         -- format-specific overrides
  created_at     timestamptz       NOT NULL DEFAULT now()
);

COMMENT ON TABLE  tournaments              IS 'A competitive bracket within an event.';
COMMENT ON COLUMN tournaments.total_rounds IS 'If NULL, the tournament engine calculates: ceil(log2(player_count)) for swiss.';
COMMENT ON COLUMN tournaments.top_cut      IS '0 = no top cut. 8 = top 8 advance to single elimination after swiss.';
COMMENT ON COLUMN tournaments.current_round IS '0 = tournament not started yet.';


-- ============================================================
-- REGISTRATIONS
-- A player entry in a tournament.
-- ============================================================

CREATE TABLE registrations (
  id              uuid                PRIMARY KEY DEFAULT gen_random_uuid(),
  tournament_id   uuid                NOT NULL REFERENCES tournaments(id) ON DELETE CASCADE,
  user_id         uuid                NOT NULL REFERENCES auth.users(id) ON DELETE CASCADE,
  status          registration_status NOT NULL DEFAULT 'registered',
  seed            int,                          -- optional manual seeding
  final_standing  int,                          -- filled in by tournament engine at end
  paid            boolean             NOT NULL DEFAULT false,
  notes           text,                         -- judge notes (drop reason, DQ reason, etc.)
  created_at      timestamptz         NOT NULL DEFAULT now(),
  UNIQUE (tournament_id, user_id)
);

COMMENT ON TABLE registrations IS 'A player entry in a tournament.';


-- ============================================================
-- DECK SUBMISSIONS
-- Optional: players submit their deck list before the tournament.
-- ============================================================

CREATE TABLE deck_submissions (
  id            uuid        PRIMARY KEY DEFAULT gen_random_uuid(),
  tournament_id uuid        NOT NULL REFERENCES tournaments(id) ON DELETE CASCADE,
  user_id       uuid        NOT NULL REFERENCES auth.users(id) ON DELETE CASCADE,
  deck_name     text,
  main_deck     jsonb       NOT NULL DEFAULT '[]', -- [{ card_name, quantity, set_code }, ...]
  sideboard     jsonb       NOT NULL DEFAULT '[]', -- same structure, max 15 cards
  commanders    jsonb       NOT NULL DEFAULT '[]', -- for Commander format only
  submitted_at  timestamptz NOT NULL DEFAULT now(),
  updated_at    timestamptz NOT NULL DEFAULT now(),
  UNIQUE (tournament_id, user_id)
);

COMMENT ON TABLE  deck_submissions           IS 'Player deck lists submitted before a tournament.';
COMMENT ON COLUMN deck_submissions.main_deck IS 'Array of { card_name, quantity, set_code }.';
COMMENT ON COLUMN deck_submissions.commanders IS 'Non-empty only for Commander/Two-Headed Giant formats.';


-- ============================================================
-- TOURNAMENT ROUNDS
-- Tracks the lifecycle of each round in a tournament.
-- ============================================================

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

COMMENT ON TABLE  tournament_rounds            IS 'Lifecycle tracking for each round in a tournament.';
COMMENT ON COLUMN tournament_rounds.is_top_cut IS 'True for playoff rounds after swiss.';


-- ============================================================
-- MATCHES
-- A single pairing between two players in a round.
-- player_b IS NULL means player_a receives a bye.
-- ============================================================

CREATE TABLE matches (
  id            uuid         PRIMARY KEY DEFAULT gen_random_uuid(),
  tournament_id uuid         NOT NULL REFERENCES tournaments(id) ON DELETE CASCADE,
  round_id      uuid         REFERENCES tournament_rounds(id) ON DELETE SET NULL,
  round_number  int          NOT NULL,
  table_number  int,
  player_a      uuid         NOT NULL REFERENCES auth.users(id),
  player_b      uuid         REFERENCES auth.users(id),  -- NULL = bye
  games_won_a   int          NOT NULL DEFAULT 0,
  games_won_b   int          NOT NULL DEFAULT 0,
  games_drawn   int          NOT NULL DEFAULT 0,
  result        match_result,                    -- NULL until reported
  status        match_status NOT NULL DEFAULT 'pending',
  is_bye        boolean      GENERATED ALWAYS AS (player_b IS NULL) STORED,
  reported_by   uuid         REFERENCES auth.users(id),
  confirmed_by  uuid         REFERENCES auth.users(id),  -- judge confirmation
  notes         text,
  created_at    timestamptz  NOT NULL DEFAULT now()
);

COMMENT ON TABLE  matches            IS 'A pairing between two players (or a bye) in a round.';
COMMENT ON COLUMN matches.player_b   IS 'NULL indicates a bye for player_a.';
COMMENT ON COLUMN matches.is_bye     IS 'Computed column: true when player_b is NULL.';
COMMENT ON COLUMN matches.games_won_a IS 'Individual game wins within the match (e.g. 2-1 = games_won_a:2, games_won_b:1).';


-- ============================================================
-- STANDINGS
-- Snapshot of standings after each completed round.
-- Written exclusively by the tournament engine (Python service).
-- ============================================================

CREATE TABLE standings (
  id            uuid        PRIMARY KEY DEFAULT gen_random_uuid(),
  tournament_id uuid        NOT NULL REFERENCES tournaments(id) ON DELETE CASCADE,
  user_id       uuid        NOT NULL REFERENCES auth.users(id) ON DELETE CASCADE,
  after_round   int         NOT NULL,            -- standings state after this round number
  rank          int         NOT NULL,
  points        int         NOT NULL DEFAULT 0,  -- 3=win, 1=draw, 0=loss
  match_wins    int         NOT NULL DEFAULT 0,
  match_losses  int         NOT NULL DEFAULT 0,
  match_draws   int         NOT NULL DEFAULT 0,
  game_wins     int         NOT NULL DEFAULT 0,
  game_losses   int         NOT NULL DEFAULT 0,
  game_draws    int         NOT NULL DEFAULT 0,
  omw_pct       numeric(5,4) NOT NULL DEFAULT 0, -- opponent match-win % (tiebreaker 1)
  ogw_pct       numeric(5,4) NOT NULL DEFAULT 0, -- opponent game-win % (tiebreaker 2)
  pgw_pct       numeric(5,4) NOT NULL DEFAULT 0, -- player game-win % (tiebreaker 3)
  created_at    timestamptz NOT NULL DEFAULT now(),
  UNIQUE (tournament_id, user_id, after_round)
);

COMMENT ON TABLE  standings         IS 'Standings snapshot after each round, written by the tournament engine.';
COMMENT ON COLUMN standings.omw_pct IS 'Opponent match-win % — standard MTG tiebreaker 1. Min floor is 0.3300.';
COMMENT ON COLUMN standings.ogw_pct IS 'Opponent game-win % — standard MTG tiebreaker 2. Min floor is 0.3300.';
COMMENT ON COLUMN standings.pgw_pct IS 'Player game-win % — standard MTG tiebreaker 3. Min floor is 0.3300.';


-- ============================================================
-- PLAYER RATINGS
-- ELO-style rating per player per game system / format.
-- Updated by the tournament engine after each event completes.
-- ============================================================

CREATE TABLE player_ratings (
  id           uuid              PRIMARY KEY DEFAULT gen_random_uuid(),
  user_id      uuid              NOT NULL REFERENCES auth.users(id) ON DELETE CASCADE,
  game_system  game_system       NOT NULL DEFAULT 'mtg',
  format       tournament_format,               -- NULL = overall rating across all formats
  rating       int               NOT NULL DEFAULT 1200,
  peak_rating  int               NOT NULL DEFAULT 1200,
  games_played int               NOT NULL DEFAULT 0,
  updated_at   timestamptz       NOT NULL DEFAULT now(),
  UNIQUE (user_id, game_system, format)
);

COMMENT ON TABLE  player_ratings        IS 'ELO-style rating per player per game system and format.';
COMMENT ON COLUMN player_ratings.rating IS 'Starting ELO is 1200 (standard in competitive card games).';
COMMENT ON COLUMN player_ratings.format IS 'NULL means the rating spans all formats for that game system.';


-- ============================================================
-- INDEXES
-- ============================================================

-- Profiles
CREATE INDEX idx_profiles_city        ON profiles (city);
CREATE INDEX idx_profiles_handle_trgm ON profiles USING gin (handle gin_trgm_ops);

-- Stores
CREATE INDEX idx_stores_city          ON stores (city);
CREATE INDEX idx_stores_slug          ON stores (slug);
CREATE INDEX idx_stores_location      ON stores (latitude, longitude);
CREATE INDEX idx_stores_name_trgm     ON stores USING gin (name gin_trgm_ops);

-- Store staff
CREATE INDEX idx_store_staff_store    ON store_staff (store_id);
CREATE INDEX idx_store_staff_user     ON store_staff (user_id);

-- Events
CREATE INDEX idx_events_store         ON events (store_id);
CREATE INDEX idx_events_start         ON events (start_datetime);
CREATE INDEX idx_events_status        ON events (status);
CREATE INDEX idx_events_game_system   ON events (game_system);

-- Tournaments
CREATE INDEX idx_tournaments_event    ON tournaments (event_id);
CREATE INDEX idx_tournaments_status   ON tournaments (status);
CREATE INDEX idx_tournaments_format   ON tournaments (format);

-- Registrations
CREATE INDEX idx_reg_tournament       ON registrations (tournament_id);
CREATE INDEX idx_reg_user             ON registrations (user_id);
CREATE INDEX idx_reg_status           ON registrations (status);

-- Tournament rounds
CREATE INDEX idx_rounds_tournament    ON tournament_rounds (tournament_id);
CREATE INDEX idx_rounds_status        ON tournament_rounds (status);

-- Matches
CREATE INDEX idx_matches_tournament   ON matches (tournament_id);
CREATE INDEX idx_matches_round        ON matches (tournament_id, round_number);
CREATE INDEX idx_matches_player_a     ON matches (player_a);
CREATE INDEX idx_matches_player_b     ON matches (player_b);
CREATE INDEX idx_matches_status       ON matches (status);

-- Standings
CREATE INDEX idx_standings_tournament ON standings (tournament_id);
CREATE INDEX idx_standings_user       ON standings (user_id);
CREATE INDEX idx_standings_round_rank ON standings (tournament_id, after_round, rank);

-- Player ratings
CREATE INDEX idx_ratings_user         ON player_ratings (user_id);
CREATE INDEX idx_ratings_format       ON player_ratings (game_system, format);
CREATE INDEX idx_ratings_top          ON player_ratings (rating DESC);

-- Deck submissions
CREATE INDEX idx_decks_tournament     ON deck_submissions (tournament_id);
CREATE INDEX idx_decks_user           ON deck_submissions (user_id);


-- ============================================================
-- TRIGGERS
-- ============================================================

-- Auto-create a profile row when a new user signs up via Supabase Auth.
CREATE OR REPLACE FUNCTION handle_new_user()
RETURNS trigger
LANGUAGE plpgsql
SECURITY DEFINER SET search_path = public
AS $$
BEGIN
  INSERT INTO public.profiles (id, handle, full_name, avatar_url)
  VALUES (
    NEW.id,
    -- Default handle: "player_" + first 8 chars of UUID (user can change later)
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


-- Auto-update updated_at timestamp on profiles.
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
-- END OF SCHEMA
-- ============================================================
