-- Combined schema + policies for MTG Bartender
-- Run this file in Supabase SQL editor or via psql against your Supabase database.

-- -----------------------
-- Schema
-- -----------------------

CREATE EXTENSION IF NOT EXISTS "pgcrypto";

CREATE TABLE IF NOT EXISTS stores (
  id uuid PRIMARY KEY DEFAULT gen_random_uuid(),
  name text NOT NULL,
  address text,
  contact_info jsonb,
  owner_user_id uuid,
  created_at timestamptz DEFAULT now()
);

CREATE TABLE IF NOT EXISTS venues (
  id uuid PRIMARY KEY DEFAULT gen_random_uuid(),
  store_id uuid REFERENCES stores(id) ON DELETE CASCADE,
  name text NOT NULL,
  capacity int DEFAULT 20,
  details jsonb,
  created_at timestamptz DEFAULT now()
);

CREATE TABLE IF NOT EXISTS events (
  id uuid PRIMARY KEY DEFAULT gen_random_uuid(),
  store_id uuid REFERENCES stores(id) ON DELETE SET NULL,
  venue_id uuid REFERENCES venues(id) ON DELETE SET NULL,
  title text NOT NULL,
  description text,
  start_datetime timestamptz,
  end_datetime timestamptz,
  capacity int DEFAULT 100,
  public boolean DEFAULT true,
  metadata jsonb,
  created_by uuid,
  created_at timestamptz DEFAULT now()
);

CREATE TABLE IF NOT EXISTS tournaments (
  id uuid PRIMARY KEY DEFAULT gen_random_uuid(),
  event_id uuid REFERENCES events(id) ON DELETE CASCADE,
  title text NOT NULL,
  format text,
  capacity int DEFAULT 64,
  entry_fee numeric DEFAULT 0,
  rules jsonb,
  status text DEFAULT 'scheduled',
  created_at timestamptz DEFAULT now()
);

CREATE TABLE IF NOT EXISTS registrations (
  id uuid PRIMARY KEY DEFAULT gen_random_uuid(),
  tournament_id uuid REFERENCES tournaments(id) ON DELETE CASCADE,
  user_id uuid,
  team_name text,
  paid boolean DEFAULT false,
  created_at timestamptz DEFAULT now()
);

CREATE TABLE IF NOT EXISTS matches (
  id uuid PRIMARY KEY DEFAULT gen_random_uuid(),
  tournament_id uuid REFERENCES tournaments(id) ON DELETE CASCADE,
  round int,
  player_a uuid,
  player_b uuid,
  score_a int,
  score_b int,
  status text DEFAULT 'pending',
  scheduled_at timestamptz,
  created_at timestamptz DEFAULT now()
);


-- ------------------------------
-- Policies / RLS
-- ------------------------------

-- Enable RLS for tables that should be access-controlled
ALTER TABLE IF EXISTS events ENABLE ROW LEVEL SECURITY;
ALTER TABLE IF EXISTS registrations ENABLE ROW LEVEL SECURITY;

-- Use simple policy names (no spaces) and drop existing ones before creating
DROP POLICY IF EXISTS allow_public_select ON events;
CREATE POLICY allow_public_select ON events FOR SELECT USING (public = true);

DROP POLICY IF EXISTS allow_authenticated_insert ON events;
CREATE POLICY allow_authenticated_insert ON events FOR INSERT WITH CHECK (auth.role() = 'authenticated');

DROP POLICY IF EXISTS registrations_insert_own ON registrations;
CREATE POLICY registrations_insert_own ON registrations FOR INSERT WITH CHECK (auth.uid() = user_id);

DROP POLICY IF EXISTS registrations_select_own ON registrations;
CREATE POLICY registrations_select_own ON registrations FOR SELECT USING (auth.uid() = user_id);

DROP POLICY IF EXISTS registrations_update_own ON registrations;
CREATE POLICY registrations_update_own ON registrations FOR UPDATE USING (auth.uid() = user_id) WITH CHECK (auth.uid() = user_id);

-- Note: The functions auth.uid() and auth.role() are provided by Supabase's Postgres auth helpers.
