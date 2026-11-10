-- The add screen draws a shared figure's notes, as the kotekan picker's cards
-- do, so it needs the figure, not just its name: `shared_kotekan_figure`
-- hands back the kotekan's columns and its hits as one JSON object, or NULL
-- when the link leads nowhere. It replaces `shared_kotekan` (name and
-- description only, from 20261107000000_kotekan_share).
--
-- JSON rather than a table so the column types the dashboard chose don't have
-- to be restated, and the sender's user_id and gangsa never leave the server.
-- Security definer for the same reason as the share migration: row-level
-- security keeps a player from reading anyone else's kotekan, and the link is
-- the capability. Safe to re-run.

drop function if exists public.shared_kotekan(text);

create or replace function public.shared_kotekan_figure(p_id text)
returns json
language sql
stable
security definer
set search_path = public
as $$
    select json_build_object(
        'id', k.id::text,
        'name', k.name,
        'description', k.description,
        'level', k.level,
        'slots_per_cycle', k.slots_per_cycle,
        'bpm', k.bpm,
        'source', k.source,
        'hits', coalesce((
            select json_agg(json_build_object(
                'kotekan_id', h.kotekan_id::text,
                'type', h.type,
                'beat_index', h.beat_index,
                'key_index', h.key_index,
                'damp_slots', h.damp_slots
            ))
            from kotekan_hits h
            where h.kotekan_id::text = p_id
        ), '[]'::json)
    )
    from kotekan k
    where k.id::text = p_id and k.user_id is not null;
$$;

revoke all on function public.shared_kotekan_figure(text) from public, anon;
grant execute on function public.shared_kotekan_figure(text) to authenticated;
