begin;
insert into auth.users(id) values('fc010000-0000-4000-8000-000000000001'),('fc010000-0000-4000-8000-000000000002');
set local role authenticated;
select set_config('request.jwt.claim.sub','fc010000-0000-4000-8000-000000000001',true);
do $$
declare job public.summary_requests; other public.summary_requests; result_count integer; payload jsonb;
begin
  select * into job from public.enqueue_summary_request('fc020000-0000-4000-8000-000000000001','phone',
    '{"id":"fc030000-0000-4000-8000-000000000001","title":"Test","video_id":"_FBivfgOvuE","url":"https://youtu.be/_FBivfgOvuE"}');
  if job.status <> 'cloud' then raise exception 'Offline Mac must route to cloud'; end if;
  update public.summary_requests set lease_until=clock_timestamp()-interval '1 second' where id=job.id;
  select * into job from public.advance_summary_request(job.id,'phone');
  if job.lease_until <= clock_timestamp() or not public.renew_summary_request(job.id,'phone','Resumed') then
    raise exception 'Resumed phone did not reclaim its cloud lease'; end if;
  perform public.summary_worker_heartbeat('mac','Test Mac',true);
  select * into job from public.enqueue_summary_request('fc020000-0000-4000-8000-000000000002','phone',
    '{"id":"fc030000-0000-4000-8000-000000000002","title":"Test","video_id":"_FBivfgOvuE","url":"https://youtu.be/_FBivfgOvuE"}');
  if job.status <> 'queued' or job.executor_id <> 'mac' then raise exception 'Online Mac must get the job'; end if;
  select * into other from public.enqueue_summary_request(job.id,'phone',job.episode);
  if other.id <> job.id or (select count(*) from public.summary_requests where id=job.id) <> 1 then raise exception 'Enqueue retry duplicated job'; end if;
  select * into job from public.claim_summary_request('mac');
  if job.status <> 'processing' then raise exception 'Mac could not claim queued request'; end if;
  select count(*) into result_count from public.claim_summary_request('mac');
  if result_count <> 0 then raise exception 'Claim duplicated processing job'; end if;
  if not public.renew_summary_request(job.id,'mac','Passage 1') then raise exception 'Active lease should renew'; end if;
  if public.renew_summary_request(job.id,'other-mac','Passage 1') then raise exception 'Other worker renewed a lease'; end if;
  update public.summary_workers set last_seen=clock_timestamp()-interval '1 minute' where device_id='mac';
  select * into job from public.advance_summary_request(job.id,'phone');
  if job.status <> 'cloud' or job.executor_id <> 'phone' then raise exception 'Lost Mac did not fall back'; end if;
  payload=jsonb_build_object('podcast_id',job.episode->>'id','brief','Saved guide','key_topics','[]'::jsonb,
    'major_takeaways','[]'::jsonb,'action_plan','[]'::jsonb,'dynamic_sections','[]'::jsonb,'generated_at','2026-10-29T06:00:00Z',
    'transcript_source','captions','model','test','action_plan_xp_granted',false);
  select count(*) into result_count from public.complete_summary_request(job.id,'mac',payload);
  if result_count <> 0 then raise exception 'Late Mac result overwrote fallback'; end if;
  select * into job from public.complete_summary_request(job.id,'phone',payload);
  if job.status <> 'completed' or not exists(select 1 from public.podcast_summaries where podcast_id=(job.episode->>'id')::uuid) then
    raise exception 'Completion must atomically publish the summary'; end if;
  perform public.merge_summary_rows(jsonb_build_array(payload || '{"brief":"Stale overwrite","generated_at":"2026-10-28T00:00:00Z"}'::jsonb));
  if exists(select 1 from public.podcast_summaries where brief='Stale overwrite') then raise exception 'Old autosave overwrote new Mac summary'; end if;
  perform public.summary_worker_heartbeat('mac','Test Mac',true);
  select * into job from public.enqueue_summary_request('fc020000-0000-4000-8000-000000000003','phone',
    '{"id":"fc030000-0000-4000-8000-000000000003","title":"Test","video_id":"_FBivfgOvuE","url":"https://youtu.be/_FBivfgOvuE"}');
  select * into job from public.claim_summary_request('mac');
  update public.summary_requests set lease_until=clock_timestamp()-interval '1 second' where id=job.id;
  select * into job from public.advance_summary_request(job.id,'phone');
  if job.status <> 'cloud' then raise exception 'Expired processing lease did not fall back'; end if;
  perform public.cancel_summary_request(job.id,'phone');
  if public.renew_summary_request(job.id,'phone','Still running') then raise exception 'Cancelled request renewed'; end if;
  select count(*) into result_count from public.complete_summary_request(job.id,'phone',payload);
  if result_count <> 0 then raise exception 'Cancelled result was published'; end if;
  perform public.summary_worker_heartbeat('mac','Test Mac',false);
  select * into job from public.enqueue_summary_request('fc020000-0000-4000-8000-000000000004','phone',
    '{"id":"fc030000-0000-4000-8000-000000000004","title":"Test","video_id":"_FBivfgOvuE","url":"https://youtu.be/_FBivfgOvuE"}');
  if job.status <> 'cloud' then raise exception 'Unready Mac should use cloud'; end if;
  if (select count(*) from public.summary_workers) <> 1 then raise exception 'Unexpected worker count'; end if;
end $$;
select set_config('request.jwt.claim.sub','fc010000-0000-4000-8000-000000000002',true);
do $$ begin
  if exists(select 1 from public.summary_requests) or exists(select 1 from public.summary_workers) then
    raise exception 'RLS leaked another account'; end if;
  if public.renew_summary_request('fc020000-0000-4000-8000-000000000001','phone','forged') then
    raise exception 'Cross-account renewal succeeded'; end if;
end $$;
reset role;
do $$ begin
 if has_table_privilege('anon','public.summary_requests','select')
   or has_function_privilege('anon','public.enqueue_summary_request(uuid,text,jsonb,text)','execute') then
   raise exception 'Anonymous routing access remains'; end if;
end $$;
rollback;
select 'PASS: offline/online routing, idempotent enqueue, single claim, leases, fallback, late-result rejection, atomic sync, stale-sync protection, cancellation, RLS, anonymous denial' as summary_routing_tests;
