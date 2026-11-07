-- High-score table for the pinball game. Run once in Supabase: SQL Editor -> New query -> Run.
create table if not exists public.scores (
  id         bigint generated always as identity primary key,
  name       text        not null check (name ~ '^[A-Z]{5}$'),        -- exactly 5 letters A-Z
  score      bigint      not null check (score >= 0 and score < 1000000000000),
  won        boolean     not null default false,                      -- defeated the boss
  created_at timestamptz not null default now()
);

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
