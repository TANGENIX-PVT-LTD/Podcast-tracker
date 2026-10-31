begin;
alter table public.summary_workers add column supports_quirky boolean not null default false;
alter table public.summary_requests add column quirky_request jsonb check(quirky_request is null or ((
 jsonb_typeof(quirky_request)='object' and (quirky_request->>'id')::uuid=id and octet_length(quirky_request::text)<=30000
 and length(trim(quirky_request->>'question')) between 1 and 4000
 and quirky_request->>'model' in ('instant','balanced','deep')
 and quirky_request->>'style' in ('concise','medium','detailed')
 and jsonb_typeof(quirky_request->'history')='array' and jsonb_array_length(quirky_request->'history')<=3) is true));
alter table public.summary_requests add column quirky_reply jsonb check(quirky_reply is null or ((
 jsonb_typeof(quirky_reply)='object' and (quirky_reply->>'id')::uuid=id and length(trim(quirky_reply->>'text')) between 1 and 50000
 and length(quirky_reply->>'source') between 1 and 100) is true));
create or replace function public.summary_worker_heartbeat(p_device text, p_name text, p_ready boolean)
returns void language sql security invoker set search_path = '' as $$
  insert into public.summary_workers(user_id, device_id, display_name, ready, last_seen)
  values(auth.uid(), p_device, p_name, p_ready, clock_timestamp())
  on conflict(user_id, device_id) do update set display_name=excluded.display_name,
    ready=excluded.ready, last_seen=excluded.last_seen, supports_quirky=false;
$$;
create or replace function public.claim_summary_request(p_worker text)
returns setof public.summary_requests language plpgsql security invoker set search_path = '' as $$
declare job uuid;
begin
  if not exists(select 1 from public.summary_workers where user_id=auth.uid() and device_id=p_worker
    and ready and last_seen > clock_timestamp()-interval '40 seconds') then return; end if;
  select id into job from public.summary_requests where user_id=auth.uid() and status='queued' and quirky_request is null
    and executor_id=p_worker and created_at > clock_timestamp()-interval '30 seconds'
    order by created_at for update skip locked limit 1;
  if job is null then return; end if;
  return query update public.summary_requests set status='processing', lease_until=clock_timestamp()+interval '45 seconds',
    progress='Preparing the episode on your Mac', updated_at=clock_timestamp()
    where id=job and user_id=auth.uid() and status='queued' returning *;
end;
$$;
create or replace function public.claim_ai_request(p_worker text)
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
    progress=case when quirky_request is null then 'Preparing the episode on your Mac' else 'Answering your question on the Mac' end, updated_at=clock_timestamp()
    where id=job and user_id=auth.uid() and status='queued' returning *;
end;
$$;
create or replace function public.complete_summary_request(p_id uuid, p_executor text, p_summary jsonb)
returns setof public.summary_requests language plpgsql security invoker set search_path = '' as $$
declare job public.summary_requests;
begin
  select * into job from public.summary_requests where id=p_id and user_id=auth.uid() for update;
  if job.id is null or job.quirky_request is not null or job.status not in ('processing','cloud') or job.executor_id is distinct from p_executor
    or job.lease_until <= clock_timestamp() then return; end if;
  if (p_summary->>'podcast_id')::uuid is distinct from (job.episode->>'id')::uuid
    or nullif(trim(p_summary->>'brief'),'') is null then raise exception 'Invalid summary result'; end if;
  perform public.merge_summary_rows(jsonb_build_array(p_summary));
  return query update public.summary_requests set status='completed', result=p_summary,
    lease_until=null, progress='Summary ready', updated_at=clock_timestamp()
    where id=p_id and user_id=auth.uid() returning *;
end;
$$;
create function public.quirky_worker_heartbeat(p_device text,p_name text,p_ready boolean)
returns void language sql security invoker set search_path='' as $$
 select public.summary_worker_heartbeat(p_device,p_name,p_ready);
 update public.summary_workers set supports_quirky=true where user_id=auth.uid() and device_id=p_device;
$$;
create function public.enqueue_quirky_request(p_id uuid,p_requester text,p_episode jsonb,p_chat jsonb,p_transcript text default null)
returns setof public.summary_requests language plpgsql security invoker set search_path='' as $$
declare worker text;
begin
 if auth.uid() is null then raise exception 'Authentication required'; end if;
 if (p_episode->>'id')::uuid is null or p_chat is null then raise exception 'Question and episode required'; end if;
 select device_id into worker from public.summary_workers where user_id=auth.uid() and ready and supports_quirky
   and last_seen>clock_timestamp()-interval '40 seconds' order by last_seen desc limit 1;
 insert into public.summary_requests(id,user_id,requester_device,episode,input_transcript,quirky_request,status,executor_id,lease_until)
 values(p_id,auth.uid(),p_requester,p_episode,p_transcript,p_chat,case when worker is null then 'cloud' else 'queued' end,
 coalesce(worker,p_requester),case when worker is null then clock_timestamp()+interval '60 seconds' else null end)
 on conflict(id) do nothing;
 return query select * from public.summary_requests where id=p_id and user_id=auth.uid() and quirky_request is not null;
end;
$$;
create function public.complete_quirky_request(p_id uuid,p_executor text,p_reply jsonb,p_transcript text default null)
returns setof public.summary_requests language sql security invoker set search_path='' as $$
 update public.summary_requests set status='completed',quirky_reply=p_reply,input_transcript=coalesce(input_transcript,p_transcript),
 lease_until=null,progress='Answer ready',updated_at=clock_timestamp()
 where id=p_id and user_id=auth.uid() and quirky_request is not null and status in ('processing','cloud')
 and executor_id=p_executor and lease_until>clock_timestamp() and nullif(trim(p_reply->>'text'),'') is not null returning *;
$$;
create function public.release_quirky_to_cloud(p_id uuid,p_worker text,p_reason text,p_transcript text default null)
returns void language sql security invoker set search_path='' as $$
 update public.summary_requests set input_transcript=coalesce(input_transcript,p_transcript)
 where id=p_id and user_id=auth.uid() and quirky_request is not null and status='processing' and executor_id=p_worker;
 select public.release_summary_to_cloud(p_id,p_worker,p_reason);
$$;
revoke all on function public.quirky_worker_heartbeat(text,text,boolean),public.claim_ai_request(text),
 public.enqueue_quirky_request(uuid,text,jsonb,jsonb,text),public.complete_quirky_request(uuid,text,jsonb,text),
 public.release_quirky_to_cloud(uuid,text,text,text) from public,anon;
grant execute on function public.quirky_worker_heartbeat(text,text,boolean),public.claim_ai_request(text),
 public.enqueue_quirky_request(uuid,text,jsonb,jsonb,text),public.complete_quirky_request(uuid,text,jsonb,text),
 public.release_quirky_to_cloud(uuid,text,text,text) to authenticated;
notify pgrst,'reload schema';
commit;
