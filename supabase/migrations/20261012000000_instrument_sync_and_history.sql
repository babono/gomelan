-- Instrument sync across devices, and practice history.
--
-- Additive only: v1 clients are still live against this database and keep
-- writing the columns they know about. Written to be safe to re-run, because
-- the schema before this file was set up by hand in the dashboard and is not
-- recorded anywhere — so nothing here assumes what already exists.
--
-- Run it in the Supabase SQL Editor (or `supabase db push`).

-- The whole instrument as the app saves it on the phone: key rectangles,
-- learned strike sound, records and stats. The existing columns stay for
-- querying; this is what another phone restores from.
alter table public.instruments
    add column if not exists profile jsonb;

-- History lists sessions newest first.
alter table public.practice_session
    add column if not exists created_at timestamptz not null default now();

create index if not exists practice_session_history_idx
    on public.practice_session (user_id, instrument_id, created_at desc);

-- Signed-in players, guests included, are the `authenticated` role. The
-- `anon` role has had SELECT revoked on practice_session, so do not assume
-- `authenticated` kept it either. Granting is a no-op where it already has it.
grant select on public.instruments to authenticated;
grant select on public.practice_session to authenticated;

-- The app now READS these tables back. Uploads already work, so insert and
-- update policies exist; a select policy may not. Added only where the table
-- has none, so an existing, possibly stricter one is left alone.
do $$
begin
    if not exists (
        select 1 from pg_policies
        where schemaname = 'public' and tablename = 'instruments'
          and cmd in ('SELECT', 'ALL')
    ) then
        create policy "instruments: owner can read"
            on public.instruments for select
            using (auth.uid() = user_id);
    end if;

    if not exists (
        select 1 from pg_policies
        where schemaname = 'public' and tablename = 'practice_session'
          and cmd in ('SELECT', 'ALL')
    ) then
        create policy "practice_session: owner can read"
            on public.practice_session for select
            using (auth.uid() = user_id);
    end if;
end
$$;
