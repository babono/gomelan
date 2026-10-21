-- How long a session was actually played, in whole seconds: the count-in
-- and any pauses left out. Shown on the results screen beside accuracy and
-- cycles.
--
-- Nullable and additive: sessions filed before this, and clients that do not
-- send it, leave it NULL rather than a 0 that would read as "not played".
alter table public.practice_session
    add column if not exists practice_seconds integer
        check (practice_seconds is null or practice_seconds >= 0);
