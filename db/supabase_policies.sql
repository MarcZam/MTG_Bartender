-- Example Supabase Row Level Security (RLS) policies for MTG Bartender
-- Run these from the SQL editor in your Supabase project after creating the tables.

-- Enable RLS on tables
ALTER TABLE IF EXISTS events ENABLE ROW LEVEL SECURITY;
ALTER TABLE IF EXISTS registrations ENABLE ROW LEVEL SECURITY;

-- Events: allow public rows to be selected, and allow authenticated users to insert
-- (Assumes events.public boolean column exists)
CREATE POLICY "Allow public select" ON events FOR SELECT USING (public = true);
CREATE POLICY "Allow authenticated insert" ON events FOR INSERT WITH CHECK (auth.role() = 'authenticated');

-- Registrations: each user may manage their own registration rows
ALTER TABLE IF EXISTS registrations ENABLE ROW LEVEL SECURITY;
CREATE POLICY "Users can insert their own registration" ON registrations FOR INSERT WITH CHECK (auth.uid() = new.user_id);
CREATE POLICY "Users can select their own registration" ON registrations FOR SELECT USING (auth.uid() = user_id);
CREATE POLICY "Users can update their own registration" ON registrations FOR UPDATE USING (auth.uid() = user_id) WITH CHECK (auth.uid() = user_id);

-- Admins or store owners: you can create more advanced policies that grant rights
-- to a 'store_admins' role or to rows where stores.owner_user_id = auth.uid().
-- Example (requires stores.owner_user_id column and a join check):
-- CREATE POLICY "Store owners can manage events" ON events FOR ALL
-- USING (exists (select 1 from stores where stores.id = events.store_id and stores.owner_user_id = auth.uid()));

-- Notes:
-- - Use the Supabase SQL editor to enable RLS and create policies after schema migration.
-- - Test policies with different users (Supabase Auth -> Users) to ensure expected behavior.
