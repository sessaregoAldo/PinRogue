-- Bug reports and suggestions from the game. Run in Supabase: SQL Editor -> New query -> Run.
-- Safe to run again. Players can only send; read and manage reports in Table Editor -> feedback.

do $$ begin
  create type public.feedback_kind as enum ('bug', 'suggestion');
exception when duplicate_object then null; end $$;

do $$ begin
  create type public.feedback_status as enum ('new', 'planned', 'done', 'wont_do');
exception when duplicate_object then null; end $$;

create table if not exists public.feedback (
  id         bigint generated always as identity primary key,
  created_at timestamptz not null default now(),
  kind       public.feedback_kind   not null,
  status     public.feedback_status not null default 'new',
  message    text not null check (char_length(message) between 3 and 500),
  name       text check (name is null or char_length(name) <= 30),
  version    text check (version is null or char_length(version) <= 20),
  machine    text check (machine is null or char_length(machine) <= 40),
  boss_round integer,
  score      double precision,
  platform   text check (platform is null or char_length(platform) <= 40)
);

create index if not exists feedback_status_idx on public.feedback (status, created_at desc);

-- Row Level Security: the game (public key) may only add new reports.
-- Nobody can read, edit or delete them without your Supabase login.
alter table public.feedback enable row level security;

drop policy if exists "send feedback" on public.feedback;
create policy "send feedback" on public.feedback for insert to anon with check (status = 'new');

revoke all on public.feedback from anon;
grant insert on public.feedback to anon;
