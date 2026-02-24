# MTG Bartender — MVP (Next.js + Supabase)

This repository contains a minimal starter for the MTG Bartender MVP: a Next.js frontend scaffold that uses Supabase for Postgres and Auth.

Quick start

1. Create a Supabase project and copy the `URL` and `anon` key.
2. From `web/` run:

```bash
cd web
npm install
```

3. Create a `.env.local` in `web/` with:

```
NEXT_PUBLIC_SUPABASE_URL=your-supabase-url
NEXT_PUBLIC_SUPABASE_ANON_KEY=your-anon-key
```

4. Run dev server:

```bash
npm run dev
```

What's included

- `web/` — Next.js app with basic auth UI and event creation/listing using Supabase client.
- `db/schema.sql` — SQL schema you can run on your Supabase Postgres to create core tables.

Next steps

- Wire Supabase Auth settings (email templates) and enable Row Level Security + policies.
- Add pairing logic, admin RBAC, and a tournament engine.
- Deploy `web/` to Vercel and connect Supabase in production.
