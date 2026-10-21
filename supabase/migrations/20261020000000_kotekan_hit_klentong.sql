-- A klentong used to be saved as "kempur". Now that the two are separate
-- instruments, kotekan_hits.hit_type (the hit_type enum) has to accept
-- "klentong" too.
alter type public.hit_type add value if not exists 'klentong' after 'kempur';
