-- Isolated database only. Reversed offline uploads, conflicting targets, and retries all roll back.
begin;
insert into auth.users(id) values ('33333333-3333-4333-8333-333333333333');
insert into public.daily_learning_activity(user_id,date_key,watched_seconds)
values ('33333333-3333-4333-8333-333333333333', current_date::text, 9999);
set local role authenticated;
select set_config('request.jwt.claim.sub', '33333333-3333-4333-8333-333333333333', true);
do $$
declare payload jsonb; response jsonb; target double precision;
begin
    select jsonb_agg(event order by day desc) into payload from (
        select current_date - n as day, jsonb_build_object('id', 'adaptive-goal/' || (current_date - n)::text,
            'day', (current_date - n)::text, 'kind', 'goal', 'value', 300, 'detail', 'daily-v2') as event from generate_series(0,2) n
        union all
        select current_date - n, jsonb_build_object('id', 'playback/mac/' || (current_date - n)::text,
            'day', (current_date - n)::text, 'kind', 'playback', 'value', 300) from generate_series(0,2) n
    ) rows;
    response := public.sync_habit_loop(payload, 0, (current_date-2)::text);
    select value into target from public.habit_events where id = 'adaptive-goal/' || current_date::text;
    if target <> 360 then raise exception 'Two completed days must advance the target to six minutes'; end if;
    perform public.sync_habit_loop(payload, 0, (current_date-2)::text);
    if (select value from public.habit_events where id = 'adaptive-goal/' || current_date::text) <> 360 then
        raise exception 'A stale device lowered the frozen target'; end if;
    if (select sum(value) from public.habit_events where kind='playback' and day=current_date) <> 300 then
        raise exception 'Retries duplicated playback'; end if;
    perform public.sync_habit_loop(jsonb_build_array(jsonb_build_object('id','playback/phone/' || current_date::text,
        'day',current_date::text,'kind','playback','value',60)), 0, (current_date-2)::text);
    if (select sum(value) from public.habit_events where kind='playback' and day=current_date) <> target then
        raise exception 'Mac and phone contributions did not complete one shared target'; end if;
end $$;
rollback;
