-- Story mode leaderboards: one board per chapter. Run in Supabase:
-- SQL Editor -> New query -> Run. Safe to run again.
-- Kept apart from public.scores so the Endless board is never affected.
create table if not exists public.story_scores (
  id         bigint generated always as identity primary key,
  created_at timestamptz not null default now(),
  chapter    text        not null check (chapter ~ '^[a-z0-9_]{1,24}$'),   -- chapter id, e.g. the first chapter's
  name       text        not null check (name ~ '^[A-Z]{2,5}$'),           -- same rule as the Endless board
  score      double precision not null check (score >= 0 and score < 'Infinity'::double precision),
  won        boolean     not null default false                            -- the chapter's boss was beaten
);

create index if not exists story_scores_board_idx on public.story_scores (chapter, score desc, created_at asc);

-- Row Level Security: anyone with the public key may read and add scores,
-- nobody (without the secret key) may edit or delete them.
alter table public.story_scores enable row level security;

drop policy if exists "read story scores" on public.story_scores;
create policy "read story scores" on public.story_scores for select to anon using (true);

drop policy if exists "submit story scores" on public.story_scores;
create policy "submit story scores" on public.story_scores for insert to anon with check (true);

grant select, insert on public.story_scores to anon;
