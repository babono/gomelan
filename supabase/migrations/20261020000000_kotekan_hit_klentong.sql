-- A klentong used to be saved as "kempur". Now that the two are separate
-- instruments, kotekan_hits.hit_type has to accept "klentong" too.
--
-- The original check constraint was created outside these migrations, so its
-- name is not known here: drop whichever check mentions hit_type.
do $$
declare c record;
begin
  for c in
    select conname from pg_constraint
    where conrelid = 'public.kotekan_hits'::regclass
      and contype = 'c'
      and pg_get_constraintdef(oid) ilike '%hit_type%'
  loop
    execute format('alter table public.kotekan_hits drop constraint %I', c.conname);
  end loop;
end $$;

alter table public.kotekan_hits
  add constraint kotekan_hits_hit_type_check
  check (hit_type in ('polos', 'sangsih', 'gong', 'kempur', 'klentong', 'kajar'));
