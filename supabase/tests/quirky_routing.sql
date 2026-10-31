begin;
insert into auth.users(id) values('fc110000-0000-4000-8000-000000000001'),('fc110000-0000-4000-8000-000000000002');
set local role authenticated;
select set_config('request.jwt.claim.sub','fc110000-0000-4000-8000-000000000001',true);
do $$
declare job public.summary_requests; other public.summary_requests; n integer;
 ep jsonb='{"id":"fc130000-0000-4000-8000-000000000001","title":"Test episode","url":"https://youtu.be/_FBivfgOvuE","video_id":"_FBivfgOvuE"}';
 chat jsonb='{"id":"fc120000-0000-4000-8000-000000000001","question":"What is the first step?","history":[],"model":"balanced","style":"concise"}';
 reply jsonb='{"id":"fc120000-0000-4000-8000-000000000001","text":"Start with an interview.","source":"Apple Intelligence · Mac"}';
begin
 perform public.summary_worker_heartbeat('old-mac','Old Mac',true);
 select * into job from public.enqueue_quirky_request('fc120000-0000-4000-8000-000000000001','phone',ep,chat);
 if job.status<>'cloud' then raise exception 'An older Mac must not receive Quirky requests'; end if;
 perform public.cancel_summary_request(job.id,'phone');
 perform public.quirky_worker_heartbeat('new-mac','New Mac',true);
 chat=jsonb_set(chat,'{id}','"fc120000-0000-4000-8000-000000000002"');
 reply=jsonb_set(reply,'{id}','"fc120000-0000-4000-8000-000000000002"');
 select * into job from public.enqueue_quirky_request('fc120000-0000-4000-8000-000000000002','phone',ep,chat);
 if job.status<>'queued' or job.executor_id<>'new-mac' then raise exception 'Quirky-capable Mac did not receive question'; end if;
 select * into other from public.enqueue_quirky_request(job.id,'phone',ep,chat);
 if other.id<>job.id or (select count(*) from public.summary_requests where id=job.id)<>1 then raise exception 'Duplicate question'; end if;
 select count(*) into n from public.claim_summary_request('new-mac');
 if n<>0 then raise exception 'Legacy summary worker claimed chat'; end if;
 select * into job from public.claim_ai_request('new-mac');
 if job.status<>'processing' or job.quirky_request->>'question'<>'What is the first step?' then raise exception 'Mac could not claim question'; end if;
 select count(*) into n from public.complete_quirky_request(job.id,'wrong-worker',reply);
 if n<>0 then raise exception 'Other worker published reply'; end if;
 select count(*) into n from public.complete_summary_request(job.id,'new-mac','{}');
 if n<>0 then raise exception 'A chat request was completed as a summary'; end if;
 select * into job from public.complete_quirky_request(job.id,'new-mac',reply,'saved transcript');
 if job.status<>'completed' or job.quirky_reply->>'text'<>'Start with an interview.' or job.input_transcript<>'saved transcript' then raise exception 'Reply/transcript did not sync atomically'; end if;
 chat=jsonb_set(chat,'{id}','"fc120000-0000-4000-8000-000000000003"');
 select * into job from public.enqueue_quirky_request('fc120000-0000-4000-8000-000000000003','phone',ep,chat);
 select * into job from public.claim_ai_request('new-mac');
 perform public.release_quirky_to_cloud(job.id,'new-mac','Local attempts failed','Mac transcript');
 select * into job from public.advance_summary_request(job.id,'phone');
 if job.status<>'cloud' or job.executor_id<>'phone' or job.input_transcript<>'Mac transcript' then raise exception 'Cloud fallback lost Mac transcript'; end if;
 select count(*) into n from public.complete_quirky_request(job.id,'new-mac',reply);
 if n<>0 then raise exception 'Late Mac overwrote cloud fallback'; end if;
 perform public.cancel_summary_request(job.id,'phone');
 select count(*) into n from public.complete_quirky_request(job.id,'phone',reply);
 if n<>0 then raise exception 'Cancelled response published'; end if;
 begin
   perform public.enqueue_quirky_request('fc120000-0000-4000-8000-000000000004','phone',ep,'{}');
   raise exception 'Missing question fields accepted';
 exception when check_violation then null;
 end;
 perform public.summary_worker_heartbeat('new-mac','Downgraded Mac',true);
 if exists(select 1 from public.summary_workers where device_id='new-mac' and supports_quirky) then raise exception 'Old heartbeat retained chat capability'; end if;
 perform public.quirky_worker_heartbeat('new-mac','New Mac',true);
 select * into job from public.enqueue_summary_request('fc120000-0000-4000-8000-000000000005','phone',ep);
 select * into job from public.claim_ai_request('new-mac');
 if job.status<>'processing' or job.quirky_request is not null then raise exception 'Unified worker broke summary requests'; end if;
 select count(*) into n from public.complete_quirky_request(job.id,'new-mac',reply);
 if n<>0 then raise exception 'A summary was completed as a chat'; end if;
end $$;
select set_config('request.jwt.claim.sub','fc110000-0000-4000-8000-000000000002',true);
do $$ begin
 if exists(select 1 from public.summary_requests) or exists(select 1 from public.summary_workers) then raise exception 'Quirky leaked across accounts'; end if;
end $$;
reset role;
do $$ begin
 if has_function_privilege('anon','public.enqueue_quirky_request(uuid,text,jsonb,jsonb,text)','execute')
 or has_function_privilege('anon','public.complete_quirky_request(uuid,text,jsonb,text)','execute') then raise exception 'Anonymous chat access'; end if;
end $$;
rollback;
select 'PASS: Quirky capability routing, idempotence, legacy isolation, fenced replies, transcript handoff, cancellation, payload validation, account RLS, anonymous denial' as quirky_routing_tests;
