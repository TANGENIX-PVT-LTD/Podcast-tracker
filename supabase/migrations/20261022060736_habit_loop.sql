begin;

create table public.habit_accounts (
    user_id uuid primary key references auth.users(id) on delete cascade,
    legacy_xp integer not null check (legacy_xp between 0 and 100000000),
    started_day date not null
);
create table public.habit_events (
    user_id uuid not null references auth.users(id) on delete cascade,
    id text not null check (length(id) between 1 and 256),
    day date not null,
    kind text not null,
    value double precision not null default 0 check (value between -100 and 86400),
    detail text not null default '' check (length(detail) <= 512),
    primary key (user_id, id)
);
create index habit_events_by_day on public.habit_events(user_id, kind, day);
alter table public.habit_accounts enable row level security;
alter table public.habit_events enable row level security;
revoke all on public.habit_accounts, public.habit_events from public, anon, authenticated;
grant select on public.habit_accounts, public.habit_events to authenticated;
create policy habit_accounts_owner_read on public.habit_accounts for select to authenticated using (auth.uid() = user_id);
create policy habit_events_owner_read on public.habit_events for select to authenticated using (auth.uid() = user_id);

create schema if not exists podtrackio_private;
revoke all on schema podtrackio_private from public, anon;
grant usage on schema podtrackio_private to authenticated;

create function podtrackio_private.sync_habit_loop(
    _events jsonb,
    _legacy_xp integer,
    _started_day text,
    _purchase text default null,
    _purchase_id text default null,
    _day text default null
) returns jsonb language plpgsql security definer set search_path = public, pg_temp as $$
declare
    owner_id uuid := auth.uid();
    account public.habit_accounts;
    event jsonb;
    event_day date;
    event_id text;
    event_kind text;
    event_value double precision;
    today date := coalesce(_day::date, current_date);
    wallet integer;
    price integer;
    learned date[];
    cursor_day date;
    freeze_count integer := 2;
    streak_count integer := 0;
    active_count integer := 0;
    wager_day date;
begin
    if owner_id is null then raise exception 'Sign in before syncing habits'; end if;
    if abs(today - current_date) > 1 then raise exception 'Check the device date before syncing'; end if;
    if jsonb_typeof(_events) <> 'array' or jsonb_array_length(_events) > 100000 or pg_column_size(_events) > 16777216 then
        raise exception 'Invalid habit event batch';
    end if;
    if _started_day !~ '^\d{4}-\d{2}-\d{2}$' or _started_day::date > today then raise exception 'Invalid habit start day'; end if;
    insert into public.habit_accounts(user_id, legacy_xp, started_day)
    values(owner_id, _legacy_xp, _started_day::date) on conflict do nothing;
    -- Serialize ingestion and purchases for this account, including retries from another device.
    select * into account from public.habit_accounts where user_id = owner_id for update;
    for event in select value from jsonb_array_elements(_events) loop
        event_id := event->>'id'; event_kind := event->>'kind';
        event_day := (event->>'day')::date;
        event_value := coalesce((event->>'value')::double precision, 0);
        if event_id is null or length(event_id) not between 1 and 256 or event_day > today
           or length(coalesce(event->>'detail', '')) > 512 then raise exception 'Invalid habit event'; end if;
        -- Spending and funded promises are emitted only by this transaction, never accepted from clients.
        if event_kind in ('spend', 'freeze-refill', 'wager', 'league-result') then continue; end if;
        if event_kind not in ('playback', 'boost-use', 'goal', 'xp', 'gems', 'boost', 'reflection', 'badge', 'league-target', 'league-result', 'baseline')
           or event_value = 'NaN'::double precision or event_value not between 0 and 86400 then
            raise exception 'Invalid habit event type or value';
        end if;
        if event_kind = 'xp' and (event_value not in (1, 10, 15, 20, 25, 100)) then raise exception 'Invalid XP receipt'; end if;
        if event_kind = 'gems' then
            if event_id = 'chest/' || event_day::text and event_value in (5, 10, 20) then null;
            elsif event_id in ('quest/' || event_day::text || '/1/gems', 'quest/' || event_day::text || '/2/gems', 'quest/' || event_day::text || '/3/gems') and event_value = 5 then null;
            elsif event_id like 'wager-reward/%' and event_value = 40 then
                wager_day := substring(event_id from 14)::date;
                if not exists(select 1 from public.habit_events where user_id = owner_id and kind = 'wager' and day = wager_day)
                   or event_day < wager_day + 6 then raise exception 'Promise is not funded or finished'; end if;
            else raise exception 'Invalid gem receipt'; end if;
        end if;
        if event_kind = 'boost' and (event_id <> 'boost/' || event_day::text or event_value <> 900) then raise exception 'Invalid boost'; end if;
        insert into public.habit_events(user_id, id, day, kind, value, detail)
        values(owner_id, event_id, event_day, event_kind, event_value, coalesce(event->>'detail', ''))
        on conflict (user_id, id) do update set value = greatest(habit_events.value, excluded.value)
        where habit_events.kind in ('playback', 'boost-use') and habit_events.kind = excluded.kind and habit_events.day = excluded.day;
    end loop;
    select coalesce(array_agg(day order by day), '{}'::date[]) into learned from (
        select date_key::date as day from public.daily_learning_activity where user_id = owner_id and watched_seconds >= 300
        union
        select day from public.habit_events where user_id = owner_id and kind = 'playback' group by day having sum(value) >= 300
    ) days;
    -- A promise pays only for seven real learning days, regardless of any streak freezes.
    for wager_day in select day from public.habit_events where user_id = owner_id and kind = 'wager' loop
        if today >= wager_day + 6 and (select count(*) from unnest(learned) d where d between wager_day and wager_day + 6) = 7 then
            insert into public.habit_events values(owner_id, 'wager-reward/' || wager_day::text, today, 'gems', 40, '') on conflict do nothing;
        else
            delete from public.habit_events where user_id = owner_id and id = 'wager-reward/' || wager_day::text;
        end if;
    end loop;
    if _purchase is not null then
        if _purchase not in ('freeze', 'wager') or _purchase_id is null then raise exception 'Invalid purchase'; end if;
        perform _purchase_id::uuid;
        if not exists(select 1 from public.habit_events where user_id = owner_id and id = 'spend/' || _purchase_id) then
            select coalesce(sum(value), 0)::integer into wallet from public.habit_events where user_id = owner_id and kind in ('gems', 'spend');
            price := case when _purchase = 'freeze' then 100 else 20 end;
            if wallet < price then raise exception 'Not enough synced gems'; end if;
            if _purchase = 'freeze' then
                cursor_day := learned[1];
                while cursor_day <= today loop
                    if cursor_day >= account.started_day then
                        freeze_count := least(2, freeze_count + (select count(*)::integer from public.habit_events where user_id = owner_id and kind = 'freeze-refill' and day = cursor_day));
                    end if;
                    if cursor_day = any(learned) then
                        streak_count := streak_count + 1;
                        if cursor_day >= account.started_day then
                            active_count := active_count + 1;
                            if active_count % 7 = 0 then freeze_count := least(2, freeze_count + 1); end if;
                        end if;
                    elsif cursor_day < today then
                        if cursor_day >= account.started_day and streak_count > 0 and freeze_count > 0 then freeze_count := freeze_count - 1;
                        else streak_count := 0; end if;
                    end if;
                    cursor_day := cursor_day + 1;
                end loop;
                if freeze_count >= 2 then raise exception 'Both freeze slots are full'; end if;
                insert into public.habit_events values(owner_id, 'freeze-refill/' || _purchase_id, today, 'freeze-refill', 1, '');
            else
                if exists(select 1 from public.habit_events where user_id = owner_id and kind = 'wager' and day > today - 7) then raise exception 'A seven-day promise is already running'; end if;
                insert into public.habit_events values(owner_id, 'wager/' || today::text, today, 'wager', 0, '20 gems staked; seven actual learning days return 40');
            end if;
            insert into public.habit_events values(owner_id, 'spend/' || _purchase_id, today, 'spend', -price, _purchase);
        end if;
    end if;
    return jsonb_build_object('legacyXP', account.legacy_xp, 'startedDay', account.started_day::text,
        'events', coalesce((select jsonb_agg(jsonb_build_object('id', id, 'day', day::text, 'kind', kind, 'value', value, 'detail', detail) order by id)
                            from public.habit_events where user_id = owner_id), '[]'::jsonb));
end;
$$;
revoke all on function podtrackio_private.sync_habit_loop(jsonb, integer, text, text, text, text) from public, anon;
grant execute on function podtrackio_private.sync_habit_loop(jsonb, integer, text, text, text, text) to authenticated;
create function public.sync_habit_loop(_events jsonb, _legacy_xp integer, _started_day text,
    _purchase text default null, _purchase_id text default null, _day text default null)
returns jsonb language sql security invoker set search_path = public, pg_temp as $$
    select podtrackio_private.sync_habit_loop(_events, _legacy_xp, _started_day, _purchase, _purchase_id, _day);
$$;
revoke all on function public.sync_habit_loop(jsonb, integer, text, text, text, text) from public, anon;
grant execute on function public.sync_habit_loop(jsonb, integer, text, text, text, text) to authenticated;
commit;
