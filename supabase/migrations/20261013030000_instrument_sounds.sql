-- Recorded gangsa key sounds (the note-capture step of adding a gangsa). Objects
-- live at `<user id>/<instrument id>/k03_a0.42_<unix>.wav` in a PRIVATE bucket:
-- the app downloads with the player's own session, so nothing needs a public
-- URL, and a recording of someone's instrument at home is theirs. The file name
-- carries the take's timestamp, and `instruments.profile` names the current
-- one per key (`sound_file`), so no table changes.
--
-- Same policy shape as the photos: a signed-in user (guests are anonymous users,
-- so they are `authenticated` too) reads, writes and deletes only inside the
-- folder named for their own id. A clip is 3 s of 16-bit mono, about 265 kB; the
-- 1 MB cap is a backstop. Safe to re-run, and safe over a bucket made by hand.

insert into storage.buckets (id, name, public, file_size_limit, allowed_mime_types)
values ('instrument-sounds', 'instrument-sounds', false, 1048576, array['audio/wav', 'audio/x-wav'])
on conflict (id) do update
    set public = excluded.public,
        file_size_limit = excluded.file_size_limit,
        allowed_mime_types = excluded.allowed_mime_types;

drop policy if exists "instrument sounds: own folder" on storage.objects;
create policy "instrument sounds: own folder"
    on storage.objects
    for all
    to authenticated
    using (
        bucket_id = 'instrument-sounds'
        and (storage.foldername(name))[1] = (select auth.uid())::text
    )
    with check (
        bucket_id = 'instrument-sounds'
        and (storage.foldername(name))[1] = (select auth.uid())::text
    );
