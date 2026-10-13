-- Gangsa photos (the October 2026 revamp replaced the pemade / kantilan type
-- with a photo). Objects live at `<user id>/<instrument id>-<version>.jpg` in a
-- PRIVATE bucket: the app downloads with the player's own session, so nothing
-- needs a public URL, and a photo of someone's instrument at home is theirs.
--
-- The policy lets a signed-in user (guests are anonymous users, so they are
-- `authenticated` too) read, write and delete only inside the folder named
-- for their own id. The app resizes to 1280 px JPEG before upload, a few
-- hundred kB; the 2 MB cap is a backstop, not the budget. Safe to re-run.

insert into storage.buckets (id, name, public, file_size_limit, allowed_mime_types)
values ('instrument-photos', 'instrument-photos', false, 2097152, array['image/jpeg'])
on conflict (id) do update
    set public = excluded.public,
        file_size_limit = excluded.file_size_limit,
        allowed_mime_types = excluded.allowed_mime_types;

drop policy if exists "instrument photos: own folder" on storage.objects;
create policy "instrument photos: own folder"
    on storage.objects
    for all
    to authenticated
    using (
        bucket_id = 'instrument-photos'
        and (storage.foldername(name))[1] = (select auth.uid())::text
    )
    with check (
        bucket_id = 'instrument-photos'
        and (storage.foldername(name))[1] = (select auth.uid())::text
    );
