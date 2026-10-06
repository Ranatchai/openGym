-- Rest-timer and day-reminder pushes for openGym on Vercel + Supabase (docs/SELF_HOSTING_VERCEL.md).
--
-- Run once in the Supabase SQL editor AFTER the migration, with the two values replaced:
--   <your-app>     the deployment's hostname, e.g. opengym.vercel.app or gym.example.com
--   <cron-secret>  the same value as the CRON_SECRET environment variable on Vercel
--
-- A self-hosted API holds a setTimeout per rest timer and checks reminders every 10 s. A function
-- holds nothing between requests, so the database keeps the clock: every 5 seconds it calls the
-- API only if a rest timer is due (no call otherwise), and once a minute always, for the day
-- reminders and housekeeping. Re-running this file replaces the jobs.

create extension if not exists pg_cron;
create extension if not exists pg_net;

insert into public.opengym_config (key, value) values
  ('tick_url', 'https://<your-app>/api/cron/tick'),
  ('cron_secret', '<cron-secret>')
on conflict (key) do update set value = excluded.value;

select cron.schedule('opengym-rest-timers', '5 seconds', $$ select public.opengym_kick(false) $$);
select cron.schedule('opengym-minute', '* * * * *', $$ select public.opengym_kick(true) $$);
