-- High-score table for PinRogue. Run in Supabase: SQL Editor -> New query -> Run.
-- Safe to run again: it also updates an existing table to the current rules.
create table if not exists public.scores (
  id         bigint generated always as identity primary key,
  name       text        not null,
  score      bigint      not null check (score >= 0 and score < 1000000000000),
  won        boolean     not null default false,                      -- defeated the boss
  created_at timestamptz not null default now()
);

-- Player names: 2 to 5 letters, A-Z only (matches the game).
alter table public.scores drop constraint if exists scores_name_check;
alter table public.scores add constraint scores_name_check check (name ~ '^[A-Z]{2,5}$');

create index if not exists scores_score_idx on public.scores (score desc, created_at asc);

-- Row Level Security: anyone with the public key may read and add scores,
-- nobody (without the secret key) may edit or delete them.
alter table public.scores enable row level security;

drop policy if exists "read scores" on public.scores;
create policy "read scores" on public.scores for select to anon using (true);

drop policy if exists "submit scores" on public.scores;
create policy "submit scores" on public.scores for insert to anon with check (true);

-- Make sure the public (anon) role can use the table through the REST API.
grant select, insert on public.scores to anon;
