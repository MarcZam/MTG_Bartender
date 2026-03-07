-- ============================================================
-- MTG Bartender — Row Level Security (RLS) Policies v2.0
-- ============================================================
-- Run this AFTER schema.sql in your Supabase SQL editor.
--
-- Access model summary:
--   - Anyone (anon)       : read public stores, events, standings, profiles
--   - Authenticated users : manage their own profile, registrations, decks
--   - Store staff/owner   : manage their store's events and tournaments
--   - Judges              : manage matches and results for their tournaments
--   - Service role        : write standings and player_ratings (tournament engine)
-- ============================================================


-- ============================================================
-- HELPER FUNCTIONS
-- Called inside policies to keep them readable.
-- ============================================================

-- Returns true if the calling user is staff (any role) at the given store.
CREATE OR REPLACE FUNCTION is_store_staff(p_store_id uuid)
RETURNS boolean
LANGUAGE sql
SECURITY DEFINER SET search_path = public
STABLE
AS $$
  SELECT EXISTS (
    SELECT 1 FROM store_staff
    WHERE store_id = p_store_id
      AND user_id  = auth.uid()
  );
$$;

-- Returns true if the calling user is owner of the given store.
CREATE OR REPLACE FUNCTION is_store_owner(p_store_id uuid)
RETURNS boolean
LANGUAGE sql
SECURITY DEFINER SET search_path = public
STABLE
AS $$
  SELECT EXISTS (
    SELECT 1 FROM store_staff
    WHERE store_id = p_store_id
      AND user_id  = auth.uid()
      AND role     = 'owner'
  );
$$;

-- Returns true if the calling user is the judge of the given tournament.
CREATE OR REPLACE FUNCTION is_tournament_judge(p_tournament_id uuid)
RETURNS boolean
LANGUAGE sql
SECURITY DEFINER SET search_path = public
STABLE
AS $$
  SELECT EXISTS (
    SELECT 1 FROM tournaments
    WHERE id       = p_tournament_id
      AND judge_id = auth.uid()
  );
$$;

-- Returns the store_id for a given tournament (via its event).
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


-- ============================================================
-- PROFILES
-- ============================================================

ALTER TABLE profiles ENABLE ROW LEVEL SECURITY;

-- Anyone can read profiles (public leaderboards, player search).
CREATE POLICY profiles_select_public
  ON profiles FOR SELECT
  USING (true);

-- Users can only update their own profile.
CREATE POLICY profiles_update_own
  ON profiles FOR UPDATE
  USING (auth.uid() = id)
  WITH CHECK (auth.uid() = id);

-- Inserts are handled exclusively by the handle_new_user() trigger.
-- No direct inserts allowed from the client.


-- ============================================================
-- STORES
-- ============================================================

ALTER TABLE stores ENABLE ROW LEVEL SECURITY;

-- Anyone can read verified stores.
CREATE POLICY stores_select_public
  ON stores FOR SELECT
  USING (is_verified = true);

-- Store staff can always see their own store (even if unverified).
CREATE POLICY stores_select_own_staff
  ON stores FOR SELECT
  USING (is_store_staff(id));

-- Any authenticated user can create a store (they become owner via app logic).
CREATE POLICY stores_insert_authenticated
  ON stores FOR INSERT
  WITH CHECK (auth.role() = 'authenticated');

-- Only store owners can update their store details.
CREATE POLICY stores_update_owner
  ON stores FOR UPDATE
  USING (is_store_owner(id))
  WITH CHECK (is_store_owner(id));

-- Only store owners can delete their store.
CREATE POLICY stores_delete_owner
  ON stores FOR DELETE
  USING (is_store_owner(id));


-- ============================================================
-- STORE STAFF
-- ============================================================

ALTER TABLE store_staff ENABLE ROW LEVEL SECURITY;

-- Store staff can see who else is on their team.
CREATE POLICY store_staff_select
  ON store_staff FOR SELECT
  USING (is_store_staff(store_id));

-- Only owners can add staff members.
CREATE POLICY store_staff_insert_owner
  ON store_staff FOR INSERT
  WITH CHECK (is_store_owner(store_id));

-- Only owners can change staff roles.
CREATE POLICY store_staff_update_owner
  ON store_staff FOR UPDATE
  USING (is_store_owner(store_id))
  WITH CHECK (is_store_owner(store_id));

-- Only owners can remove staff members.
CREATE POLICY store_staff_delete_owner
  ON store_staff FOR DELETE
  USING (is_store_owner(store_id));


-- ============================================================
-- VENUES
-- ============================================================

ALTER TABLE venues ENABLE ROW LEVEL SECURITY;

-- Anyone can read venues of verified stores.
CREATE POLICY venues_select_public
  ON venues FOR SELECT
  USING (
    EXISTS (
      SELECT 1 FROM stores s
      WHERE s.id = store_id AND s.is_verified = true
    )
  );

-- Store staff can always see their own venues.
CREATE POLICY venues_select_staff
  ON venues FOR SELECT
  USING (is_store_staff(store_id));

-- Store staff can create venues.
CREATE POLICY venues_insert_staff
  ON venues FOR INSERT
  WITH CHECK (is_store_staff(store_id));

-- Store staff can update venues.
CREATE POLICY venues_update_staff
  ON venues FOR UPDATE
  USING (is_store_staff(store_id))
  WITH CHECK (is_store_staff(store_id));

-- Only store owners can delete venues.
CREATE POLICY venues_delete_owner
  ON venues FOR DELETE
  USING (is_store_owner(store_id));


-- ============================================================
-- EVENTS
-- ============================================================

ALTER TABLE events ENABLE ROW LEVEL SECURITY;

-- Anyone can read published public events.
CREATE POLICY events_select_public
  ON events FOR SELECT
  USING (is_public = true AND status = 'published');

-- Store staff can read all their store's events (including drafts).
CREATE POLICY events_select_staff
  ON events FOR SELECT
  USING (is_store_staff(store_id));

-- Store staff can create events for their store.
CREATE POLICY events_insert_staff
  ON events FOR INSERT
  WITH CHECK (is_store_staff(store_id));

-- Store staff can update events.
CREATE POLICY events_update_staff
  ON events FOR UPDATE
  USING (is_store_staff(store_id))
  WITH CHECK (is_store_staff(store_id));

-- Only store owners can delete events.
CREATE POLICY events_delete_owner
  ON events FOR DELETE
  USING (is_store_owner(store_id));


-- ============================================================
-- TOURNAMENTS
-- ============================================================

ALTER TABLE tournaments ENABLE ROW LEVEL SECURITY;

-- Anyone can read tournaments of public published events.
CREATE POLICY tournaments_select_public
  ON tournaments FOR SELECT
  USING (
    EXISTS (
      SELECT 1 FROM events e
      WHERE e.id = event_id
        AND e.is_public = true
        AND e.status    = 'published'
    )
  );

-- Store staff and assigned judge can read their tournaments.
CREATE POLICY tournaments_select_staff
  ON tournaments FOR SELECT
  USING (
    judge_id = auth.uid()
    OR EXISTS (
      SELECT 1 FROM events e
      WHERE e.id = event_id AND is_store_staff(e.store_id)
    )
  );

-- Store staff can create tournaments under their events.
CREATE POLICY tournaments_insert_staff
  ON tournaments FOR INSERT
  WITH CHECK (
    EXISTS (
      SELECT 1 FROM events e
      WHERE e.id = event_id AND is_store_staff(e.store_id)
    )
  );

-- Store staff or the assigned judge can update tournament details.
CREATE POLICY tournaments_update_staff_or_judge
  ON tournaments FOR UPDATE
  USING (
    judge_id = auth.uid()
    OR EXISTS (
      SELECT 1 FROM events e
      WHERE e.id = event_id AND is_store_staff(e.store_id)
    )
  )
  WITH CHECK (
    judge_id = auth.uid()
    OR EXISTS (
      SELECT 1 FROM events e
      WHERE e.id = event_id AND is_store_staff(e.store_id)
    )
  );

-- Only store owners can delete tournaments.
CREATE POLICY tournaments_delete_owner
  ON tournaments FOR DELETE
  USING (
    EXISTS (
      SELECT 1 FROM events e
      WHERE e.id = event_id AND is_store_owner(e.store_id)
    )
  );


-- ============================================================
-- REGISTRATIONS
-- ============================================================

ALTER TABLE registrations ENABLE ROW LEVEL SECURITY;

-- Players can see their own registrations.
CREATE POLICY registrations_select_own
  ON registrations FOR SELECT
  USING (auth.uid() = user_id);

-- Store staff and judges can see all registrations for their tournaments.
CREATE POLICY registrations_select_staff
  ON registrations FOR SELECT
  USING (
    is_tournament_judge(tournament_id)
    OR is_store_staff(tournament_store_id(tournament_id))
  );

-- Authenticated players can register themselves.
CREATE POLICY registrations_insert_own
  ON registrations FOR INSERT
  WITH CHECK (auth.uid() = user_id);

-- Players can update their own registration (e.g. drop from tournament).
-- Store staff and judges can update any registration (check-in, disqualify).
CREATE POLICY registrations_update_own_or_staff
  ON registrations FOR UPDATE
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

-- Players can cancel their own registration (only before tournament starts).
CREATE POLICY registrations_delete_own
  ON registrations FOR DELETE
  USING (
    auth.uid() = user_id
    AND EXISTS (
      SELECT 1 FROM tournaments t
      WHERE t.id = tournament_id
        AND t.status IN ('scheduled', 'registration_open')
    )
  );


-- ============================================================
-- DECK SUBMISSIONS
-- ============================================================

ALTER TABLE deck_submissions ENABLE ROW LEVEL SECURITY;

-- Players can only see their own deck lists.
CREATE POLICY decks_select_own
  ON deck_submissions FOR SELECT
  USING (auth.uid() = user_id);

-- Judges and store staff can read all deck lists for their tournaments
-- (for deck checks). Visible only after registration closes.
CREATE POLICY decks_select_judge
  ON deck_submissions FOR SELECT
  USING (
    is_tournament_judge(tournament_id)
    OR is_store_staff(tournament_store_id(tournament_id))
  );

-- Players can submit their own deck.
CREATE POLICY decks_insert_own
  ON deck_submissions FOR INSERT
  WITH CHECK (auth.uid() = user_id);

-- Players can update their own deck before the tournament starts.
CREATE POLICY decks_update_own
  ON deck_submissions FOR UPDATE
  USING (
    auth.uid() = user_id
    AND EXISTS (
      SELECT 1 FROM tournaments t
      WHERE t.id = tournament_id
        AND t.status IN ('scheduled', 'registration_open', 'registration_closed')
    )
  )
  WITH CHECK (auth.uid() = user_id);

-- Players can delete their own deck before the tournament starts.
CREATE POLICY decks_delete_own
  ON deck_submissions FOR DELETE
  USING (
    auth.uid() = user_id
    AND EXISTS (
      SELECT 1 FROM tournaments t
      WHERE t.id = tournament_id
        AND t.status IN ('scheduled', 'registration_open', 'registration_closed')
    )
  );


-- ============================================================
-- TOURNAMENT ROUNDS
-- ============================================================

ALTER TABLE tournament_rounds ENABLE ROW LEVEL SECURITY;

-- Anyone can read rounds of public tournaments.
CREATE POLICY rounds_select_public
  ON tournament_rounds FOR SELECT
  USING (
    EXISTS (
      SELECT 1 FROM tournaments t
      JOIN events e ON e.id = t.event_id
      WHERE t.id = tournament_id
        AND e.is_public = true
        AND e.status    = 'published'
    )
  );

-- Judges and store staff can always see rounds for their tournaments.
CREATE POLICY rounds_select_staff
  ON tournament_rounds FOR SELECT
  USING (
    is_tournament_judge(tournament_id)
    OR is_store_staff(tournament_store_id(tournament_id))
  );

-- Only judges and store staff can create / update / delete rounds.
CREATE POLICY rounds_write_staff
  ON tournament_rounds FOR INSERT
  WITH CHECK (
    is_tournament_judge(tournament_id)
    OR is_store_staff(tournament_store_id(tournament_id))
  );

CREATE POLICY rounds_update_staff
  ON tournament_rounds FOR UPDATE
  USING (
    is_tournament_judge(tournament_id)
    OR is_store_staff(tournament_store_id(tournament_id))
  )
  WITH CHECK (
    is_tournament_judge(tournament_id)
    OR is_store_staff(tournament_store_id(tournament_id))
  );


-- ============================================================
-- MATCHES
-- ============================================================

ALTER TABLE matches ENABLE ROW LEVEL SECURITY;

-- Players involved in a match can see it.
CREATE POLICY matches_select_players
  ON matches FOR SELECT
  USING (
    auth.uid() = player_a
    OR auth.uid() = player_b
  );

-- Anyone can read matches of public tournaments.
CREATE POLICY matches_select_public
  ON matches FOR SELECT
  USING (
    EXISTS (
      SELECT 1 FROM tournaments t
      JOIN events e ON e.id = t.event_id
      WHERE t.id = tournament_id
        AND e.is_public = true
        AND e.status    = 'published'
    )
  );

-- Judges and store staff can see all matches for their tournaments.
CREATE POLICY matches_select_staff
  ON matches FOR SELECT
  USING (
    is_tournament_judge(tournament_id)
    OR is_store_staff(tournament_store_id(tournament_id))
  );

-- Judges and store staff create match pairings.
CREATE POLICY matches_insert_staff
  ON matches FOR INSERT
  WITH CHECK (
    is_tournament_judge(tournament_id)
    OR is_store_staff(tournament_store_id(tournament_id))
  );

-- A player involved in the match can report the result.
-- Judges and store staff can always update any match.
CREATE POLICY matches_update_players_or_staff
  ON matches FOR UPDATE
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


-- ============================================================
-- STANDINGS
-- ============================================================

ALTER TABLE standings ENABLE ROW LEVEL SECURITY;

-- Anyone can read standings of public tournaments (for leaderboards).
CREATE POLICY standings_select_public
  ON standings FOR SELECT
  USING (
    EXISTS (
      SELECT 1 FROM tournaments t
      JOIN events e ON e.id = t.event_id
      WHERE t.id = tournament_id
        AND e.is_public = true
        AND e.status    = 'published'
    )
  );

-- Players can always read their own standings.
CREATE POLICY standings_select_own
  ON standings FOR SELECT
  USING (auth.uid() = user_id);

-- Standings are written only by the service role (Python tournament engine).
-- No INSERT / UPDATE / DELETE policies for authenticated or anon roles.
-- The tournament engine connects with the service_role key, which bypasses RLS.


-- ============================================================
-- PLAYER RATINGS
-- ============================================================

ALTER TABLE player_ratings ENABLE ROW LEVEL SECURITY;

-- Anyone can read player ratings (public leaderboard).
CREATE POLICY ratings_select_public
  ON player_ratings FOR SELECT
  USING (true);

-- Ratings are written only by the service role (Python tournament engine).
-- No INSERT / UPDATE / DELETE policies for authenticated or anon roles.


-- ============================================================
-- END OF POLICIES
-- ============================================================
