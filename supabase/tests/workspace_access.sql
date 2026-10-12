-- Run in the SQL editor or psql; checks existing rows without changing user data.
begin;
do $$
declare
  tables text[] := array['podcasts', 'user_stats', 'categories',
    'daily_learning_activity', 'podcast_summaries', 'podcast_collections'];
  expected bigint[] := '{}';
  owner_id uuid;
  owner_column text;
  actual bigint;
  foreign_rows bigint;
  i integer;
begin
  select user_id into owner_id from public.podcasts limit 1;
  if owner_id is null then
    raise exception 'Add an owned podcast in a test backend before this check';
  end if;
  for i in 1..array_length(tables, 1) loop
    if has_table_privilege('anon', 'public.' || tables[i], 'select') then
      raise exception 'Anonymous access remains on %', tables[i];
    end if;
    owner_column := case when tables[i] = 'user_stats' then 'id' else 'user_id' end;
    execute format('select count(*) from public.%I where %I::text = $1',
      tables[i], owner_column) into actual using owner_id::text;
    expected := array_append(expected, actual);
  end loop;
  perform set_config('request.jwt.claims',
    json_build_object('sub', owner_id, 'role', 'authenticated')::text, true);
  perform set_config('request.jwt.claim.sub', owner_id::text, true);
  set local role authenticated;
  for i in 1..array_length(tables, 1) loop
    owner_column := case when tables[i] = 'user_stats' then 'id' else 'user_id' end;
    execute format('select count(*), count(*) filter (where %I::text <> $1) from public.%I',
      owner_column, tables[i]) into actual, foreign_rows using owner_id::text;
    if actual <> expected[i] or foreign_rows <> 0 then
      raise exception 'Owner isolation failed on %', tables[i];
    end if;
  end loop;
  reset role;
end $$;
rollback;
