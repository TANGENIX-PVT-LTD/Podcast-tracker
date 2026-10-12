begin;

-- Podcast ownership must be non-null and indexed because every mobile and
-- desktop request is scoped by auth.uid(). SET NOT NULL deliberately fails
-- if legacy unowned rows exist instead of silently assigning them to a user.
alter table public.podcasts alter column user_id set not null;

do $$
begin
  if not exists (
    select 1 from pg_constraint
    where conrelid = 'public.podcasts'::regclass
      and contype = 'f'
      and conname = 'podcasts_user_id_fkey'
  ) then
    alter table public.podcasts
      add constraint podcasts_user_id_fkey
      foreign key (user_id) references auth.users(id) on delete cascade;
  end if;
end $$;

create index if not exists podcasts_user_id_idx on public.podcasts(user_id);

drop policy if exists "podcasts_owner_all" on public.podcasts;
create policy "podcasts_owner_all" on public.podcasts
  for all to authenticated
  using ((select auth.uid()) = user_id)
  with check ((select auth.uid()) = user_id);

notify pgrst, 'reload schema';

commit;
