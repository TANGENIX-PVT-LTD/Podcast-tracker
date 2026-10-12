begin;

-- Legacy permissive policies override owner policies because PostgreSQL ORs them.
drop policy if exists "Allow all access on podcasts" on public.podcasts;
drop policy if exists "Allow all access on user_stats" on public.user_stats;

alter table public.podcasts enable row level security;
alter table public.user_stats enable row level security;
alter table public.categories enable row level security;
alter table public.daily_learning_activity enable row level security;
alter table public.podcast_summaries enable row level security;
alter table public.podcast_collections enable row level security;

drop policy if exists "user_stats_owner_all" on public.user_stats;
create policy "user_stats_owner_all" on public.user_stats
  for all to authenticated
  using ((select auth.uid())::text = id::text)
  with check ((select auth.uid())::text = id::text);

alter policy "podcasts_owner_all" on public.podcasts to authenticated;
alter policy "categories_owner_all" on public.categories to authenticated;
alter policy "activity_owner_all" on public.daily_learning_activity to authenticated;
alter policy "summaries_owner_all" on public.podcast_summaries to authenticated;
alter policy "podcast_collections_owner_all" on public.podcast_collections to authenticated;

revoke all on public.podcasts, public.user_stats, public.categories,
  public.daily_learning_activity, public.podcast_summaries,
  public.podcast_collections from anon, public;
grant select, insert, update, delete on public.podcasts, public.user_stats,
  public.categories, public.daily_learning_activity, public.podcast_summaries,
  public.podcast_collections to authenticated;

-- Abort rather than publish if any workspace table remains anonymously readable.
do $$
declare
  workspace_table text;
begin
  foreach workspace_table in array array['podcasts', 'user_stats', 'categories',
    'daily_learning_activity', 'podcast_summaries', 'podcast_collections']
  loop
    if has_table_privilege('anon', 'public.' || workspace_table, 'select') then
      raise exception 'Anonymous read privilege remains on %', workspace_table;
    end if;
    if not (select relrowsecurity from pg_class
      where oid = ('public.' || workspace_table)::regclass) then
      raise exception 'RLS is disabled on %', workspace_table;
    end if;
  end loop;
end $$;

notify pgrst, 'reload schema';
commit;
