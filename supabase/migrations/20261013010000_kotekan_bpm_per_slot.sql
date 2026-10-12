-- kotekan.bpm is pulses per minute of the GRID SLOT, not the quarter note:
-- the app reads it back as strokeMs = 60000 / bpm, one stroke per slot. The
-- hand-made check was written for a musical tempo, so it passed the built-ins
-- (250 ms a slot, bpm 240) and rejected every pattern from Create Kotek — a
-- quarter of 88 in sixteenths is already 352 a slot — with 23514, which the
-- app reported as a lost connection.
--
-- Positive is the only rule that holds for every subdivision a player can
-- write: the slot is the gcd of their note positions, so its rate has no
-- useful upper bound. Safe to re-run.

alter table public.kotekan drop constraint if exists kotekan_bpm_check;
alter table public.kotekan add constraint kotekan_bpm_check check (bpm > 0);
