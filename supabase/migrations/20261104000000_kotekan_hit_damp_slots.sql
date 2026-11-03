-- Where the hand stops a stroke. A polos or sangsih hit can carry damp_slots:
-- how many grid slots the bilah rings before it is damped, set in Studio by
-- dragging the stroke's damp cap, a whole block (a slot) at a time.
--
-- NULL is the default and what every existing row keeps: the stroke rings
-- until the half's next stroke, and is damped there if that is another bilah
-- (Kotekan.makeSong). So nothing needs back-filling, and the built-ins stay
-- as they are.
--
-- Only the two halves have a ring to stop; the app never writes one on a gong,
-- kempur, klentong or kajar row. The check leaves the hit's type column alone
-- (the table was made in the dashboard, and the app and an earlier migration
-- name it differently).
--
-- Safe to re-run, and over the draft of this file that made the column real
-- (half-slot damping, since dropped): the type change converts it in place.

alter table public.kotekan_hits
  add column if not exists damp_slots smallint;

alter table public.kotekan_hits
  alter column damp_slots type smallint using round(damp_slots)::smallint;

alter table public.kotekan_hits drop constraint if exists kotekan_hits_damp_slots_check;
alter table public.kotekan_hits add constraint kotekan_hits_damp_slots_check
  check (damp_slots is null or damp_slots > 0);

comment on column public.kotekan_hits.damp_slots is
  'Slots this polos/sangsih stroke rings before it is damped. NULL: until the half''s next stroke.';
