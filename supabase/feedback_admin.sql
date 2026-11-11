-- In-game report viewer (main menu > Feedback > View reports).
-- Run in Supabase: SQL Editor -> New query -> Run. Safe to run again.
--
-- The game's public key still has no direct access to the feedback table. It can
-- only call feedback_list / feedback_delete, which check the PIN first. The PIN is
-- checked here, on the server, and stored only as a bcrypt hash; 5 wrong PINs in
-- a row lock the viewer for 15 minutes.
--
-- The PIN is NOT in this file (the repo is public). Set or change it by running
-- the last statement with your PIN in place of CHANGE-ME.

create extension if not exists pgcrypto with schema extensions;

-- Private schema: not exposed through the API.
create schema if not exists feedback_admin;
revoke all on schema feedback_admin from public, anon, authenticated;

create table if not exists feedback_admin.settings (
  id              integer primary key default 1 check (id = 1),
  pin_hash        text not null,
  failed_attempts integer not null default 0,
  locked_until    timestamptz
);
revoke all on feedback_admin.settings from public, anon, authenticated;

-- Returns null when the PIN is right, otherwise the reason it was refused.
create or replace function feedback_admin.check_pin(pin text) returns text
language plpgsql security definer set search_path = '' as $$
declare
  s feedback_admin.settings%rowtype;
begin
  select * into s from feedback_admin.settings where id = 1 for update;
  if not found then
    return 'no PIN has been set up';
  end if;
  if s.locked_until is not null and s.locked_until > now() then
    return 'too many wrong PINs, try again in '
      || ceil(extract(epoch from s.locked_until - now()) / 60)::int || ' min';
  end if;
  if pin is not null and extensions.crypt(pin, s.pin_hash) = s.pin_hash then
    update feedback_admin.settings set failed_attempts = 0, locked_until = null where id = 1;
    return null;
  end if;
  if s.failed_attempts + 1 >= 5 then
    update feedback_admin.settings
       set failed_attempts = 0, locked_until = now() + interval '15 minutes' where id = 1;
    return 'too many wrong PINs, try again in 15 min';
  end if;
  update feedback_admin.settings set failed_attempts = s.failed_attempts + 1 where id = 1;
  return 'wrong PIN';
end $$;

-- {ok, error, entries: [{id, created_unix, kind, status, message, name, version,
--  machine, boss_round, score, platform}]}, newest first (up to 200).
create or replace function public.feedback_list(pin text) returns json
language plpgsql security definer set search_path = '' as $$
declare
  err text;
begin
  err := feedback_admin.check_pin(pin);
  if err is not null then
    return json_build_object('ok', false, 'error', err);
  end if;
  return json_build_object('ok', true, 'error', '', 'entries', coalesce((
    select json_agg(row_to_json(f) order by f.created_unix desc)
    from (
      select id, extract(epoch from created_at)::double precision as created_unix,
             kind, status, message, name, version, machine, boss_round, score, platform
      from public.feedback
      order by created_at desc
      limit 200
    ) f), '[]'::json));
end $$;

-- {ok, error, deleted}: deleted is 1, or 0 if the report was already gone.
create or replace function public.feedback_delete(pin text, feedback_id bigint) returns json
language plpgsql security definer set search_path = '' as $$
declare
  err text;
  n integer;
begin
  err := feedback_admin.check_pin(pin);
  if err is not null then
    return json_build_object('ok', false, 'error', err);
  end if;
  delete from public.feedback where id = feedback_id;
  get diagnostics n = row_count;
  return json_build_object('ok', true, 'error', '', 'deleted', n);
end $$;

revoke all on function feedback_admin.check_pin(text) from public, anon, authenticated;
revoke all on function public.feedback_list(text) from public;
revoke all on function public.feedback_delete(text, bigint) from public;
grant execute on function public.feedback_list(text) to anon;
grant execute on function public.feedback_delete(text, bigint) to anon;

-- Set (or change) the PIN, which also clears any lockout: remove the "--" in front
-- of the next four lines and put your PIN in place of CHANGE-ME.
-- insert into feedback_admin.settings (id, pin_hash)
-- values (1, extensions.crypt('CHANGE-ME', extensions.gen_salt('bf')))
-- on conflict (id) do update
--   set pin_hash = excluded.pin_hash, failed_attempts = 0, locked_until = null;
