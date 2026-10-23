-- Run against an isolated test database after the habit migration. All fixture writes roll back.
begin;
insert into auth.users(id) values ('11111111-1111-4111-8111-111111111111'), ('22222222-2222-4222-8222-222222222222');
set local role authenticated;
select set_config('request.jwt.claim.sub', '11111111-1111-4111-8111-111111111111', true);
do $$
declare
    response jsonb;
    payload jsonb;
    duplicate jsonb;
    wallet integer;
begin
    select jsonb_agg(jsonb_build_object('id', 'quest/' || (current_date - n)::text || '/1/gems', 'day', (current_date - n)::text,
        'kind', 'gems', 'value', 5, 'detail', '')) into payload from generate_series(0, 4) n;
    payload := payload || jsonb_build_array(jsonb_build_object('id', 'playback/test/' || current_date::text, 'day', current_date::text, 'kind', 'playback', 'value', 300));
    response := public.sync_habit_loop(payload, 100, (current_date - 5)::text);
    duplicate := public.sync_habit_loop(payload, 100, (current_date - 5)::text);
    if response <> duplicate then raise exception 'Duplicate ingestion changed receipts'; end if;
    if (select count(*) from public.habit_events) <> 6 then raise exception 'Unexpected event count'; end if;
    perform public.sync_habit_loop(jsonb_build_array(jsonb_build_object('id', 'playback/test/' || current_date::text,
        'day', current_date::text, 'kind', 'playback', 'value', 200)), 100, (current_date - 5)::text);
    if (select value from public.habit_events where kind = 'playback') <> 300 then raise exception 'A stale upload erased progress'; end if;
    perform public.sync_habit_loop('[]', 9999, (current_date - 5)::text, 'wager', '33333333-3333-4333-8333-333333333333');
    perform public.sync_habit_loop('[]', 9999, (current_date - 5)::text, 'wager', '33333333-3333-4333-8333-333333333333');
    select sum(value)::integer into wallet from public.habit_events where kind in ('gems', 'spend');
    if wallet <> 5 then raise exception 'Purchase retry spent twice'; end if;
    if (select legacy_xp from public.habit_accounts) <> 100 then raise exception 'Legacy XP baseline changed'; end if;
    begin
        perform public.sync_habit_loop('[]', 100, (current_date - 5)::text, 'freeze', '44444444-4444-4444-8444-444444444444');
        raise exception 'Overspend unexpectedly succeeded';
    exception when others then
        if sqlerrm = 'Overspend unexpectedly succeeded' then raise; end if;
    end;
    begin
        perform public.sync_habit_loop(jsonb_build_array(jsonb_build_object('id', 'playback/negative/' || current_date::text,
            'day', current_date::text, 'kind', 'playback', 'value', -1)), 100, (current_date - 5)::text);
        raise exception 'Negative contribution unexpectedly succeeded';
    exception when others then
        if sqlerrm <> 'Invalid habit event type or value' then raise; end if;
    end;
    begin
        insert into public.habit_events(user_id, id, day, kind) values(auth.uid(), 'direct-write', current_date, 'gems');
        raise exception 'Direct writes unexpectedly succeeded';
    exception when insufficient_privilege then null;
    end;
end $$;
select set_config('request.jwt.claim.sub', '22222222-2222-4222-8222-222222222222', true);
do $$
begin
    if exists(select 1 from public.habit_events) or exists(select 1 from public.habit_accounts) then raise exception 'Cross-account habit data exposed'; end if;
    perform public.sync_habit_loop('[]', 0, current_date::text);
    if (select count(*) from public.habit_accounts) <> 1 then raise exception 'Second account was not isolated'; end if;
end $$;
reset role;
do $$
begin
    if has_table_privilege('anon', 'public.habit_events', 'select')
       or has_function_privilege('anon', 'public.sync_habit_loop(jsonb,integer,text,text,text,text)', 'execute') then
        raise exception 'Anonymous habit access was granted';
    end if;
end $$;
rollback;
