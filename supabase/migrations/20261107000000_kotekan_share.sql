-- Sharing a kotekan by link (https://www.kotek.app/share/<id>, or kotek://k/<id>).
--
-- Adding a shared figure COPIES it: a new kotekan row and its hits, owned by
-- whoever added it and filed on the gangsa they chose. Not a reference to the
-- sender's row — an edit or a delete on either side leaves the other alone,
-- and nobody's catalogue ever holds a row they cannot change.
--
-- Row-level security keeps a player from reading anyone else's kotekan, so
-- both functions are security definer and do the one read sharing needs. The
-- link is the capability: player figures have random uuid ids. Built-ins
-- (user_id NULL) are on every phone already and are never copied.
--
-- The table was made in the dashboard and its id type is not recorded here,
-- so ids are compared as text and the new one is a uuid, which assigns to a
-- text or a uuid column alike. Safe to re-run.

-- The name, for the add dialog, before anything is copied.
create or replace function public.shared_kotekan(p_id text)
returns table (name text, description text)
language sql
stable
security definer
set search_path = public
as $$
    select k.name, k.description
    from kotekan k
    where k.id::text = p_id and k.user_id is not null;
$$;

create or replace function public.copy_shared_kotekan(p_id text, p_instrument_id uuid)
returns text
language plpgsql
security definer
set search_path = public
as $$
declare
    uid uuid := auth.uid();
    new_id uuid := gen_random_uuid();
    src kotekan%rowtype;
begin
    -- Guests are anonymous users: sharing needs an account that outlives the
    -- phone, so the app asks them to link an Apple ID first. Checked here too.
    if uid is null or coalesce((auth.jwt() ->> 'is_anonymous')::boolean, false) then
        raise exception 'sign in to add a shared kotekan' using errcode = '42501';
    end if;

    if p_instrument_id is not null and not exists (
        select 1 from instruments where id::text = p_instrument_id::text and user_id = uid
    ) then
        raise exception 'not your gangsa' using errcode = '42501';
    end if;

    select * into src from kotekan where id::text = p_id and user_id is not null;
    if not found then
        raise exception 'no such kotekan' using errcode = 'P0002';
    end if;

    insert into kotekan (id, user_id, instrument_id, name, description, level, slots_per_cycle, bpm, source)
    values (new_id, uid, p_instrument_id, src.name, src.description, src.level,
            src.slots_per_cycle, src.bpm, src.source);

    insert into kotekan_hits (kotekan_id, type, beat_index, key_index, damp_slots)
    select new_id, h.type, h.beat_index, h.key_index, h.damp_slots
    from kotekan_hits h
    where h.kotekan_id::text = p_id;

    return new_id::text;
end
$$;

revoke all on function public.shared_kotekan(text) from public, anon;
revoke all on function public.copy_shared_kotekan(text, uuid) from public, anon;
grant execute on function public.shared_kotekan(text) to authenticated;
grant execute on function public.copy_shared_kotekan(text, uuid) to authenticated;
