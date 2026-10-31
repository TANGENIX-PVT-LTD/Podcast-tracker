begin;

create table public.summary_workers (
  user_id uuid not null references auth.users(id) on delete cascade,
  device_id text not null check (length(device_id) between 1 and 128),
  display_name text not null check (length(display_name) between 1 and 200),
  ready boolean not null default false,
  last_seen timestamptz not null default now(),
  primary key (user_id, device_id)
);
create table public.summary_requests (
  id uuid primary key,
  user_id uuid not null references auth.users(id) on delete cascade,
  requester_device text not null check (length(requester_device) between 1 and 128),
  episode jsonb not null check (jsonb_typeof(episode) = 'object'
    and episode->>'video_id' ~ '^[A-Za-z0-9_-]{11}$'
    and length(episode->>'title') between 1 and 2000),
  input_transcript text check (octet_length(input_transcript) <= 4000000),
  status text not null check (status in ('queued','processing','cloud','completed','failed','cancelled')),
  executor_id text,
  lease_until timestamptz,
  progress text not null default '',
  error_message text,
  result jsonb,
  created_at timestamptz not null default now(),
  updated_at timestamptz not null default now()
);
create index summary_requests_owner_queue on public.summary_requests(user_id, status, created_at);
alter table public.summary_workers enable row level security;
alter table public.summary_requests enable row level security;
create policy summary_workers_owner on public.summary_workers for all to authenticated
  using ((select auth.uid()) = user_id) with check ((select auth.uid()) = user_id);
create policy summary_requests_owner on public.summary_requests for all to authenticated
  using ((select auth.uid()) = user_id) with check ((select auth.uid()) = user_id);
revoke all on public.summary_workers, public.summary_requests from public, anon;
grant select, insert, update, delete on public.summary_workers, public.summary_requests to authenticated;

create function public.summary_worker_heartbeat(p_device text, p_name text, p_ready boolean)
returns void language sql security invoker set search_path = '' as $$
  insert into public.summary_workers(user_id, device_id, display_name, ready, last_seen)
  values(auth.uid(), p_device, p_name, p_ready, clock_timestamp())
  on conflict(user_id, device_id) do update set display_name=excluded.display_name,
    ready=excluded.ready, last_seen=excluded.last_seen;
$$;

create function public.enqueue_summary_request(p_id uuid, p_requester text, p_episode jsonb, p_transcript text default null)
returns setof public.summary_requests language plpgsql security invoker set search_path = '' as $$
declare worker text;
begin
  if auth.uid() is null then raise exception 'Authentication required'; end if;
  if (p_episode->>'id')::uuid is null then raise exception 'Episode ID required'; end if;
  select device_id into worker from public.summary_workers
    where user_id=auth.uid() and ready and last_seen > clock_timestamp()-interval '40 seconds'
    order by last_seen desc limit 1;
  insert into public.summary_requests(id,user_id,requester_device,episode,input_transcript,status,executor_id,lease_until)
    values(p_id,auth.uid(),p_requester,p_episode,p_transcript,
      case when worker is null then 'cloud' else 'queued' end,
      coalesce(worker,p_requester),case when worker is null then clock_timestamp()+interval '60 seconds' else null end)
    on conflict(id) do nothing;
  return query select * from public.summary_requests where id=p_id and user_id=auth.uid();
end;
$$;

create function public.claim_summary_request(p_worker text)
returns setof public.summary_requests language plpgsql security invoker set search_path = '' as $$
declare job uuid;
begin
  if not exists(select 1 from public.summary_workers where user_id=auth.uid() and device_id=p_worker
    and ready and last_seen > clock_timestamp()-interval '40 seconds') then return; end if;
  select id into job from public.summary_requests where user_id=auth.uid() and status='queued'
    and executor_id=p_worker and created_at > clock_timestamp()-interval '30 seconds'
    order by created_at for update skip locked limit 1;
  if job is null then return; end if;
  return query update public.summary_requests set status='processing', lease_until=clock_timestamp()+interval '45 seconds',
    progress='Preparing the episode on your Mac', updated_at=clock_timestamp()
    where id=job and user_id=auth.uid() and status='queued' returning *;
end;
$$;

create function public.advance_summary_request(p_id uuid, p_requester text)
returns setof public.summary_requests language plpgsql security invoker set search_path = '' as $$
begin
  update public.summary_requests r set status='cloud', executor_id=r.requester_device,
      lease_until=clock_timestamp()+interval '60 seconds', progress='Using cloud fallback', updated_at=clock_timestamp()
    where r.id=p_id and r.user_id=auth.uid() and r.requester_device=p_requester
      and r.status in ('queued','processing') and (
        (r.status='queued' and r.created_at < clock_timestamp()-interval '30 seconds')
        or (r.status='processing' and r.lease_until < clock_timestamp())
        or r.created_at < clock_timestamp()-interval '20 minutes'
        or not exists(select 1 from public.summary_workers w where w.user_id=r.user_id
          and w.device_id=r.executor_id and w.last_seen > clock_timestamp()-interval '40 seconds')
      );
  -- A foreground phone can resume its own cloud lease after an OS suspension.
  update public.summary_requests set lease_until=clock_timestamp()+interval '60 seconds', updated_at=clock_timestamp()
    where id=p_id and user_id=auth.uid() and requester_device=p_requester and status='cloud'
      and executor_id=p_requester and lease_until < clock_timestamp();
  return query select * from public.summary_requests where id=p_id and user_id=auth.uid();
end;
$$;

create function public.renew_summary_request(p_id uuid, p_executor text, p_progress text)
returns boolean language plpgsql security invoker set search_path = '' as $$
declare affected integer;
begin
  update public.summary_requests set lease_until=clock_timestamp()+interval '45 seconds',
    progress=left(p_progress,300), updated_at=clock_timestamp()
    where id=p_id and user_id=auth.uid() and executor_id=p_executor
      and status in ('processing','cloud') and lease_until > clock_timestamp();
  get diagnostics affected = row_count;
  return affected=1;
end;
$$;

create function public.release_summary_to_cloud(p_id uuid, p_worker text, p_reason text)
returns void language sql security invoker set search_path = '' as $$
  update public.summary_requests set status='cloud', executor_id=requester_device,
    lease_until=clock_timestamp()+interval '60 seconds', error_message=left(p_reason,1000),
    progress='Using cloud fallback', updated_at=clock_timestamp()
    where id=p_id and user_id=auth.uid() and status='processing' and executor_id=p_worker;
$$;

create function public.merge_summary_rows(p_rows jsonb)
returns void language plpgsql security invoker set search_path = '' as $$
declare p_summary jsonb;
begin
  for p_summary in select value from jsonb_array_elements(p_rows) loop
  insert into public.podcast_summaries(user_id,podcast_id,brief,key_topics,major_takeaways,action_plan,dynamic_sections,
    generated_at,transcript_source,model,action_plan_xp_granted)
  values(auth.uid(),(p_summary->>'podcast_id')::uuid,p_summary->>'brief',
    p_summary->'key_topics',p_summary->'major_takeaways',p_summary->'action_plan',p_summary->'dynamic_sections',
    (p_summary->>'generated_at')::timestamptz,p_summary->>'transcript_source',p_summary->>'model',
    coalesce((p_summary->>'action_plan_xp_granted')::boolean,false))
  on conflict(user_id,podcast_id) do update set brief=excluded.brief,key_topics=excluded.key_topics,
    major_takeaways=excluded.major_takeaways,action_plan=excluded.action_plan,dynamic_sections=excluded.dynamic_sections,
    generated_at=excluded.generated_at,transcript_source=excluded.transcript_source,model=excluded.model,
    action_plan_xp_granted=excluded.action_plan_xp_granted
    where public.podcast_summaries.generated_at <= excluded.generated_at;
  end loop;
end;
$$;

create function public.complete_summary_request(p_id uuid, p_executor text, p_summary jsonb)
returns setof public.summary_requests language plpgsql security invoker set search_path = '' as $$
declare job public.summary_requests;
begin
  select * into job from public.summary_requests where id=p_id and user_id=auth.uid() for update;
  if job.id is null or job.status not in ('processing','cloud') or job.executor_id is distinct from p_executor
    or job.lease_until <= clock_timestamp() then return; end if;
  if (p_summary->>'podcast_id')::uuid is distinct from (job.episode->>'id')::uuid
    or nullif(trim(p_summary->>'brief'),'') is null then raise exception 'Invalid summary result'; end if;
  perform public.merge_summary_rows(jsonb_build_array(p_summary));
  return query update public.summary_requests set status='completed', result=p_summary,
    lease_until=null, progress='Summary ready', updated_at=clock_timestamp()
    where id=p_id and user_id=auth.uid() returning *;
end;
$$;

create function public.cancel_summary_request(p_id uuid, p_requester text)
returns void language sql security invoker set search_path = '' as $$
  update public.summary_requests set status='cancelled',lease_until=null,updated_at=clock_timestamp()
    where id=p_id and user_id=auth.uid() and requester_device=p_requester and status in ('queued','processing','cloud');
$$;

create function public.fail_summary_request(p_id uuid, p_executor text, p_reason text)
returns void language sql security invoker set search_path = '' as $$
  update public.summary_requests set status='failed',lease_until=null,error_message=left(p_reason,1000),updated_at=clock_timestamp()
    where id=p_id and user_id=auth.uid() and executor_id=p_executor and status='cloud';
$$;

revoke all on function public.summary_worker_heartbeat(text,text,boolean),
  public.enqueue_summary_request(uuid,text,jsonb,text), public.claim_summary_request(text),
  public.advance_summary_request(uuid,text), public.renew_summary_request(uuid,text,text),
  public.release_summary_to_cloud(uuid,text,text), public.complete_summary_request(uuid,text,jsonb),
  public.cancel_summary_request(uuid,text), public.fail_summary_request(uuid,text,text), public.merge_summary_rows(jsonb) from public, anon;
grant execute on function public.summary_worker_heartbeat(text,text,boolean),
  public.enqueue_summary_request(uuid,text,jsonb,text), public.claim_summary_request(text),
  public.advance_summary_request(uuid,text), public.renew_summary_request(uuid,text,text),
  public.release_summary_to_cloud(uuid,text,text), public.complete_summary_request(uuid,text,jsonb),
  public.cancel_summary_request(uuid,text), public.fail_summary_request(uuid,text,text), public.merge_summary_rows(jsonb) to authenticated;

notify pgrst, 'reload schema';
commit;
