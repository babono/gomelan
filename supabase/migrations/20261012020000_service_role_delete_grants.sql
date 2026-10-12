-- The delete-account Edge Function runs as `service_role`. That role bypasses
-- RLS but still needs table privileges, and the hand-made schema had them
-- revoked (42501 "permission denied for table practice_session" on the first
-- delete). Grant exactly what the function does: read ids, delete rows.

grant select, delete on public.practice_session to service_role;
grant select, delete on public.kotekan_hits to service_role;
grant select, delete on public.kotekan to service_role;
grant select, delete on public.instrument_keys to service_role;
grant select, delete on public.instruments to service_role;
