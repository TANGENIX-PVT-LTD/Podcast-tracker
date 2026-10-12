begin;

-- Original tables predate the checked-in migrations; keep fresh installs complete.
create table if not exists public.podcasts (
  id uuid primary key default gen_random_uuid(),
  user_id uuid not null references auth.users(id) on delete cascade,
  title text not null,
  url text not null,
  youtube_video_id text not null,
  thumbnail_u_r_l text,
  thumbnail_url text,
  date_added timestamptz default now(),
  notes text default '',
  total_watched_seconds double precision default 0,
  last_watched_date timestamptz,
  last_playback_position double precision default 0,
  is_completed boolean default false,
  category text default 'General',
  duration double precision
);

create table if not exists public.user_stats (
  id text primary key,
  user_id text,
  total_seconds_watched double precision default 0,
  current_streak integer default 0,
  longest_streak integer default 0,
  last_active_date timestamptz,
  total_x_p integer default 0,
  total_xp integer default 0,
  weekly_goal_hours double precision default 5,
  daily_goal_minutes double precision default 30,
  weekly_seconds_watched double precision default 0,
  daily_seconds_watched double precision default 0,
  week_start_date timestamptz,
  day_start_date timestamptz,
  unlocked_achievement_ids jsonb default '[]'::jsonb,
  podcasts_completed integer default 0,
  total_notes_taken integer default 0,
  total_podcasts_added integer default 0,
  sessions_count integer default 0,
  longest_session_seconds double precision default 0
);

alter table public.podcasts enable row level security;
alter table public.user_stats enable row level security;
commit;
