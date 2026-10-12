-- Strike controllers (PRD §3.6, §7): one controller shared between any number
-- of a player's gangsa, each gangsa with its own input → key map.
--
--   controllers                 one row per (user, controller)
--   instruments.controller_id   which controller this gangsa uses (at most one)
--   instrument_keys.sensor_input  which input's sensor sits on this bilah
--
-- Additive and safe to re-run, like the files before it: v1 clients are live
-- and keep writing the columns they know about. Run it BEFORE shipping a build
-- that syncs controllers — that build selects and writes these columns, and
-- PostgREST rejects the whole instrument write if they are missing.

create table if not exists public.controllers (
    id               uuid primary key default gen_random_uuid(),
    user_id          uuid not null references auth.users (id) on delete cascade,
    -- ESP32 eFuse MAC, 12 uppercase hex digits. Prototype firmware without the
    -- INFO characteristic is stored as LEGACY-<this phone's CoreBluetooth id>.
    hardware_id      text not null,
    name             text not null,
    input_count      smallint not null default 14,
    has_plug_detect  boolean not null default false,
    firmware_version text,
    created_at       timestamptz not null default now(),
    unique (user_id, hardware_id)
);

alter table public.controllers enable row level security;

do $$
begin
    if not exists (
        select 1 from pg_policies
        where schemaname = 'public' and tablename = 'controllers'
    ) then
        create policy "controllers: owner"
            on public.controllers for all
            using (auth.uid() = user_id)
            with check (auth.uid() = user_id);
    end if;
end
$$;

grant select, insert, update, delete on public.controllers to authenticated;

-- Deleting a controller leaves its gangsa without one rather than failing:
-- the gangsa and its key map are still worth keeping.
alter table public.instruments
    add column if not exists controller_id uuid
        references public.controllers (id) on delete set null,
    -- Inputs that had a sensor plugged in at setup. Null without plug detect.
    add column if not exists controller_inputs smallint[],
    add column if not exists controller_set_up_at timestamptz;

-- `sensor_id` (from the hand-made schema) is left alone: its type was never
-- recorded and v1 clients are live. This is the column the app writes.
alter table public.instrument_keys
    add column if not exists sensor_input smallint
        check (sensor_input between 0 and 31);

-- The delete-account Edge Function runs as service_role; see
-- 20261012020000_service_role_delete_grants.sql.
grant select, delete on public.controllers to service_role;
