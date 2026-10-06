-- openGym on Supabase (docs/SELF_HOSTING_VERCEL.md).
--
-- The API keeps the same shapes it keeps in ./data on a self-hosted instance; only where they
-- live changes. Every table below is reached by the API alone, with the service-role key, over
-- PostgREST. Row level security is switched on with no policy at all, so the anon and
-- authenticated keys a browser could hold read and write nothing here.
--
--   opengym_rows    db.json, one row per entry: users, creds, subs, invites, deviceLinks.
--                   Written as field-level patches (opengym_db_apply), so two function
--                   instances changing different fields of one user do not undo each other.
--   opengym_state   state-<uid>.json, with the revision as a column for the compare-and-write.
--   opengym_eph     what the long-running server held in memory and a function cannot:
--                   WebAuthn challenges, pairing codes, live presence. Each row has an expiry.
--   opengym_kv      the session secret, the VAPID keys, the sign-in throttle's counters.
--   opengym_audit   audit.log.
--   opengym_timers  pending rest-timer pushes, fired by pg_cron through opengym_kick().
--   opengym_config  the URL and secret opengym_kick() calls the API with.

create table if not exists public.opengym_rows (
  coll text not null,
  key  text not null,
  seq  bigserial,
  data jsonb not null,
  primary key (coll, key)
);

create table if not exists public.opengym_state (
  uid        text primary key,
  rev        integer not null default 0,
  data       jsonb not null,
  updated_at timestamptz not null default now()
);

create table if not exists public.opengym_eph (
  ns   text not null,
  key  text not null,
  data jsonb not null,
  exp  bigint not null,             -- epoch ms
  primary key (ns, key)
);

create table if not exists public.opengym_kv (
  key  text primary key,
  data jsonb not null
);

create table if not exists public.opengym_audit (
  id  bigserial primary key,
  ts  bigint not null,              -- epoch ms
  ev  text not null,
  ok  boolean not null,
  rec jsonb not null
);
create index if not exists opengym_audit_ts on public.opengym_audit (ts);

create table if not exists public.opengym_timers (
  key     text primary key,         -- `${uid}:${deviceId}`
  uid     text not null,
  fire_at bigint not null,          -- epoch ms
  payload jsonb not null
);
create index if not exists opengym_timers_fire on public.opengym_timers (fire_at);

-- The sign-in throttle (rate-limit.js), one row per counted key, changed by deltas so that
-- instances counting at the same moment add up instead of overwriting each other.
create table if not exists public.opengym_throttle (
  lim  text not null,               -- 'burst' | 'addr' | 'acct'
  key  text not null,
  e    jsonb not null,
  primary key (lim, key)
);

create table if not exists public.opengym_config (
  key   text primary key,
  value text not null
);

alter table public.opengym_rows   enable row level security;
alter table public.opengym_state  enable row level security;
alter table public.opengym_eph    enable row level security;
alter table public.opengym_kv     enable row level security;
alter table public.opengym_audit  enable row level security;
alter table public.opengym_timers enable row level security;
alter table public.opengym_config enable row level security;
alter table public.opengym_throttle enable row level security;
-- Supabase grants anon and authenticated everything on new public tables; RLS stops reads and
-- writes, not TRUNCATE. Nobody but the service role has any business here.
revoke all on public.opengym_rows, public.opengym_state, public.opengym_eph, public.opengym_kv,
  public.opengym_audit, public.opengym_timers, public.opengym_config, public.opengym_throttle
  from anon, authenticated;

-- Applies the changes one saveDb() found, in order, in one transaction.
--   {op:'put',   c, k, data}        insert or replace the whole entry
--   {op:'patch', c, k, set, unset}  merge `set` into an entry that still exists, drop `unset`
--   {op:'del',   c, k}              remove it
-- A patch on an entry another instance has deleted meanwhile is dropped, never re-created:
-- a profile an admin removed must not come back because someone's last sync was being noted.
-- Guards, for what must happen once: `expect` {field: value} must still hold on the stored
-- entry (an invite's usedBy still null), `must` says the entry must still be there (a device
-- link being burned). A guard that fails raises opengym_conflict and nothing is applied.
create or replace function public.opengym_db_apply(ops jsonb) returns void
language plpgsql set search_path = '' as $$
declare op jsonb; cur jsonb; f text;
begin
  for op in select value from jsonb_array_elements(ops) loop
    if op ? 'expect' or coalesce((op->>'must')::boolean, false) then
      select data into cur from public.opengym_rows where coll = op->>'c' and key = op->>'k' for update;
      if cur is null and coalesce((op->>'must')::boolean, false) then
        raise exception 'opengym_conflict: % % is gone', op->>'c', op->>'k';
      end if;
      if cur is not null and op ? 'expect' then
        for f in select jsonb_object_keys(op->'expect') loop
          if (cur->f) is distinct from nullif(op->'expect'->f, 'null'::jsonb) then
            raise exception 'opengym_conflict: % % changed', op->>'c', op->>'k';
          end if;
        end loop;
      end if;
    end if;
    if op->>'op' = 'put' then
      insert into public.opengym_rows (coll, key, data) values (op->>'c', op->>'k', op->'data')
      on conflict (coll, key) do update set data = excluded.data;
    elsif op->>'op' = 'patch' then
      update public.opengym_rows
         set data = (data - coalesce(array(select jsonb_array_elements_text(op->'unset')), '{}'::text[]))
                    || coalesce(op->'set', '{}'::jsonb)
       where coll = op->>'c' and key = op->>'k';
    elsif op->>'op' = 'del' then
      delete from public.opengym_rows where coll = op->>'c' and key = op->>'k';
    end if;
  end loop;
end $$;

-- PUT /api/data's compare-and-write. Writes only over revision `p_expect`; otherwise answers
-- with what is there, so the route can hand it back in its 409.
create or replace function public.opengym_state_write(p_uid text, p_expect integer, p_data jsonb) returns jsonb
language plpgsql set search_path = '' as $$
declare cur record;
begin
  update public.opengym_state set rev = p_expect + 1, data = p_data, updated_at = now()
   where uid = p_uid and rev = p_expect;
  if found then return jsonb_build_object('ok', true, 'rev', p_expect + 1); end if;
  if p_expect = 0 then
    insert into public.opengym_state (uid, rev, data) values (p_uid, 1, p_data) on conflict (uid) do nothing;
    if found then return jsonb_build_object('ok', true, 'rev', 1); end if;
  end if;
  select rev, data into cur from public.opengym_state where uid = p_uid;
  return jsonb_build_object('ok', false, 'rev', coalesce(cur.rev, 0), 'state', cur.data);
end $$;

-- Takes every rest timer that is due, so that of two ticks running at once each push goes once.
create or replace function public.opengym_timers_claim() returns setof public.opengym_timers
language sql set search_path = '' as $$
  delete from public.opengym_timers
   where fire_at <= (extract(epoch from clock_timestamp()) * 1000)::bigint
  returning *;
$$;

-- Keeps the newest `p_max` audit rows that are not older than `p_cut` (0 = no cap of that kind).
create or replace function public.opengym_audit_compact(p_max integer, p_cut bigint) returns void
language plpgsql set search_path = '' as $$
declare edge bigint;
begin
  if p_cut > 0 then delete from public.opengym_audit where ts < p_cut; end if;
  if p_max > 0 then
    select id into edge from public.opengym_audit order by id desc offset p_max limit 1;
    if edge is not null then delete from public.opengym_audit where id <= edge; end if;
  end if;
end $$;

-- Called by pg_cron. Calls the API's tick route when a rest timer is due, or always when
-- `p_minute` (the minute job: day reminders and housekeeping). Needs the pg_net extension and
-- the two opengym_config rows `tick_url` and `cron_secret` (docs/SELF_HOSTING_VERCEL.md).
create or replace function public.opengym_kick(p_minute boolean default false) returns void
language plpgsql set search_path = '' as $$
declare url text; secret text;
begin
  if not p_minute and not exists (
    select 1 from public.opengym_timers where fire_at <= (extract(epoch from clock_timestamp()) * 1000)::bigint
  ) then return; end if;
  select value into url from public.opengym_config where key = 'tick_url';
  select value into secret from public.opengym_config where key = 'cron_secret';
  if url is null or secret is null then return; end if;
  perform net.http_post(
    url := url,
    headers := jsonb_build_object('Authorization', 'Bearer ' || secret, 'Content-Type', 'application/json'),
    body := jsonb_build_object('minute', p_minute)
  );
end $$;

-- The cron tick's first look: whose reminder is on, without reading anyone's history.
create or replace function public.opengym_reminders(p_uids text[]) returns table (uid text, reminder jsonb)
language sql stable set search_path = '' as $$
  select s.uid, s.data->'reminder' from public.opengym_state s
   where s.uid = any(p_uids) and (s.data->'reminder'->>'on')::boolean is true;
$$;

-- Whole documents for a list of profiles, by POST: a list in the URL outgrows its limit.
create or replace function public.opengym_states(p_uids text[]) returns table (uid text, data jsonb)
language sql stable set search_path = '' as $$
  select s.uid, s.data from public.opengym_state s where s.uid = any(p_uids);
$$;

-- One line per profile for the admin list: how many workouts, the last one's date, the last push.
-- Entries that are not objects are skipped, as records() does on the file-backed side.
create or replace function public.opengym_state_summaries() returns table (uid text, workouts integer, last_workout text, ts bigint)
language sql stable set search_path = '' as $$
  select s.uid,
         (select count(*)::integer from jsonb_array_elements(case when jsonb_typeof(s.data->'workouts') = 'array' then s.data->'workouts' else '[]'::jsonb end) w
           where jsonb_typeof(w) = 'object'),
         (select w->>'d' from jsonb_array_elements(case when jsonb_typeof(s.data->'workouts') = 'array' then s.data->'workouts' else '[]'::jsonb end) with ordinality as t(w, i)
           where jsonb_typeof(w) = 'object' order by i desc limit 1),
         case when jsonb_typeof(s.data->'_ts') = 'number' then (s.data->>'_ts')::numeric::bigint end
    from public.opengym_state s;
$$;

-- Applies one request's throttle changes as deltas (server.js, throttleDeltas):
--   {lim, key, op:'del'}                       the key was cleared or swept
--   {lim, key, op:'set', e}                    the key started over (a new window, a forgotten count)
--   {lim, key, op:'add', dn | dc, until, last} n (backoff) or count (window) grows by the delta;
--                                              until and last only move forward
create or replace function public.opengym_throttle_apply(p_ops jsonb) returns void
language plpgsql set search_path = '' as $$
declare op jsonb; cur jsonb;
begin
  for op in select value from jsonb_array_elements(p_ops) loop
    if op->>'op' = 'del' then
      delete from public.opengym_throttle where lim = op->>'lim' and key = op->>'key';
    elsif op->>'op' = 'set' then
      insert into public.opengym_throttle (lim, key, e) values (op->>'lim', op->>'key', op->'e')
      on conflict (lim, key) do update set e = excluded.e;
    else
      select e into cur from public.opengym_throttle where lim = op->>'lim' and key = op->>'key' for update;
      if cur is null then
        insert into public.opengym_throttle (lim, key, e) values (op->>'lim', op->>'key', op->'e')
        on conflict (lim, key) do nothing;
      elsif op ? 'dc' then
        update public.opengym_throttle set e = jsonb_set(cur, '{count}', to_jsonb(coalesce((cur->>'count')::bigint, 0) + (op->>'dc')::bigint))
         where lim = op->>'lim' and key = op->>'key';
      else
        update public.opengym_throttle set e = cur
          || jsonb_build_object('n', greatest(0, coalesce((cur->>'n')::bigint, 0) + (op->>'dn')::bigint))
          || jsonb_build_object('until', greatest(coalesce((cur->>'until')::bigint, 0), coalesce((op->>'until')::bigint, 0)))
          || jsonb_build_object('last', greatest(coalesce((cur->>'last')::bigint, 0), coalesce((op->>'last')::bigint, 0)))
         where lim = op->>'lim' and key = op->>'key';
      end if;
    end if;
  end loop;
end $$;

-- Nobody but the service role (and the cron job, which runs as postgres) calls these.
revoke all on function public.opengym_db_apply(jsonb) from public, anon, authenticated;
revoke all on function public.opengym_state_write(text, integer, jsonb) from public, anon, authenticated;
revoke all on function public.opengym_timers_claim() from public, anon, authenticated;
revoke all on function public.opengym_audit_compact(integer, bigint) from public, anon, authenticated;
revoke all on function public.opengym_kick(boolean) from public, anon, authenticated;
revoke all on function public.opengym_reminders(text[]) from public, anon, authenticated;
revoke all on function public.opengym_states(text[]) from public, anon, authenticated;
revoke all on function public.opengym_state_summaries() from public, anon, authenticated;
revoke all on function public.opengym_throttle_apply(jsonb) from public, anon, authenticated;
grant execute on function public.opengym_reminders(text[]) to service_role;
grant execute on function public.opengym_states(text[]) to service_role;
grant execute on function public.opengym_state_summaries() to service_role;
grant execute on function public.opengym_throttle_apply(jsonb) to service_role;
grant execute on function public.opengym_db_apply(jsonb) to service_role;
grant execute on function public.opengym_state_write(text, integer, jsonb) to service_role;
grant execute on function public.opengym_timers_claim() to service_role;
grant execute on function public.opengym_audit_compact(integer, bigint) to service_role;
