# Vercel + Supabase

Runs openGym with no server of your own. The app and the API deploy to Vercel as one project,
and everything the API would keep in `./data` lives in a Supabase Postgres database instead.

> Your data then lives with two providers, Vercel and Supabase, instead of on a disk you own.
> If keeping it on your own disk is why you picked openGym, use [Docker Compose](SELF_HOSTING.md).

## What is different from a self-hosted instance

| | Docker Compose | Vercel + Supabase |
| --- | --- | --- |
| Users, passkeys, workout data | `./data/*.json` | Supabase tables (`opengym_*`) |
| Rest-timer and day-reminder pushes | timers inside the API | `pg_cron` calls `/api/cron/tick` |
| Photos and videos on custom exercises | yes | **off**: a function accepts at most 4.5 MB per request. They stay on the device |
| AI Coach | optional | **off**: its jobs run for minutes |
| Exercise images and GIFs | downloaded into `./media` | served from the dataset's jsDelivr CDN |
| Largest synced profile | 5 MB | about 4.5 MB (Vercel's request limit) |

Everything else works the same, including passkeys, password sign-in, invites, the admin
dashboard, the audit log, phone pairing, device links, and "sign out everywhere".

## 1. Supabase

1. Create a project at [supabase.com](https://supabase.com).
2. In the **SQL editor**, run [`supabase/migrations/20261006000000_opengym.sql`](../supabase/migrations/20261006000000_opengym.sql).
   If you use the Supabase CLI, run `supabase db push` from the repository instead.
3. In **Project Settings → API**, note the **Project URL** and the **`service_role`** key.
   The service-role key bypasses row level security, so it goes into Vercel's environment and nowhere else.
   The tables have RLS switched on and no policies, so the public `anon` key can read none of them.

## 2. Vercel

1. Import the repository as a new project. Keep **Root Directory** at the repository root:
   [`vercel.json`](../vercel.json) defines two [Services](https://vercel.com/docs/services),
   `web` (`frontend/`) and `api` (`api/server.js`), and routes `/api/*` to the API on the same origin.
   Passkeys need that single origin.
2. Set these **Environment Variables**. Scope `SUPABASE_*` and `CRON_SECRET` to **Production**
   only. Otherwise every preview deployment of every branch runs with full access to your data:

| Variable | Required | Value |
| --- | --- | --- |
| `SUPABASE_URL` | yes | the Project URL, e.g. `https://abcd.supabase.co` |
| `SUPABASE_SERVICE_ROLE_KEY` | yes | the `service_role` key |
| `CRON_SECRET` | yes | a long random string, e.g. `openssl rand -hex 32` |
| `RP_ID` / `ORIGIN` | on a custom domain | `gym.example.com` / `https://gym.example.com`. Without them the project's production `*.vercel.app` domain is used |
| `SESSION_SECRET` | no | signs the session cookies. Unset, one is generated on first boot and stored in `opengym_kv` |
| `VAPID_PUBLIC_KEY` / `VAPID_PRIVATE_KEY` | no | push keys. Unset, they are generated once and stored in `opengym_kv` |

   All the other variables in [SELF_HOSTING.md](SELF_HOSTING.md) work as documented, including
   `ADMIN_UIDS`, `INVITE_ONLY`, `ALLOW_GUEST`, `PASSWORD_LOGIN`, `DEFAULT_LANG`, `SESSION_DAYS` and `AUDIT_*`.
   `DATA_DIR`, `PORT` and the `MEDIA_*` variables have no effect here.
3. Deploy.

A passkey is bound to the hostname it was made on. Decide on the final domain before anyone
signs up. Passkeys made on `*.vercel.app` do not work once you move to a custom domain.

## 3. Push notifications (pg_cron)

Open [`supabase/cron.sql`](../supabase/cron.sql), replace `<your-app>` with your deployment's
hostname and `<cron-secret>` with the value of `CRON_SECRET`, then run it in the SQL editor.
It enables `pg_cron` and `pg_net` and schedules two jobs:

- every 5 seconds, `opengym_kick(false)` calls the API only when a rest timer is due. Otherwise nothing runs.
- every minute, `opengym_kick(true)` sends the day reminders, clears expired challenges and codes, and trims the audit log.

Rest-timer alerts therefore arrive up to about 5 seconds late. If you skip this step,
everything else still works, but no pushes are sent while the app is in the background.

To check it, look at the `cron.job_run_details` table in Supabase and the function logs on Vercel.
The minute job answers `{"ok":true,"fired":0}`.

On Vercel Pro you can call `GET /api/cron/tick` from [Vercel Cron](https://vercel.com/docs/cron-jobs)
every minute instead. Vercel sends `CRON_SECRET` as the bearer token on its own. Rest timers then
fire on the next minute, so `pg_cron` is still the better clock. Use one clock, not both: two
minute jobs that overlap can each send the same day reminder.

A rest timer is taken off the queue before its push is sent. If the tick fails at that moment,
that one alert is lost.

## How the API runs here

When both `SUPABASE_*` variables are set, `api/server.js` switches to [`api/store-supabase.js`](../api/store-supabase.js).
It talks to PostgREST over `fetch`, so the API still has two dependencies. Each request:

1. waits for the previous request on the same function instance, so one instance answers one request at a time;
2. reloads the users, passkeys and push subscriptions from the database;
3. runs the same route code as a self-hosted instance;
4. sends its answer only after its writes have landed.

Concurrent instances never overwrite each other's work:

- **Profiles and credentials** are saved as per-field patches (`opengym_db_apply`). Two instances
  that change different fields of one profile both keep their change. A stale instance cannot,
  for example, put back a session version that "sign out everywhere" just bumped.
- **Workout data** is written with the same compare-and-write as on disk (`opengym_state_write`).
  A push that loses a race gets the usual `409` with the current document.
- **Challenges and pairing codes** are deleted in the same statement that reads them, so each
  one works once across all instances.
- **What must happen once** is checked by the database when it saves (`opengym_db_apply`
  guards): an invite is used once, a device link is redeemed once, and a session version is
  never bumped over another bump. The request that loses such a race gets a `409` and nothing
  of it is saved.
- **Sign-in throttle counts** (`opengym_throttle`) are saved as increments, so wrong passwords
  sent to several instances at once all count. Requests that arrive in the same instant can still
  get one extra attempt before a pause, because each instance decides on the count it loaded.
- **Not guarded:** two sign-ups racing for the same password-login name or e-mail can both
  succeed, and a passkey added in the same instant as "sign out everywhere" survives it.
  Both need the two requests to land within a few milliseconds of each other.

## Moving an existing instance

There is no importer yet. One way to move an existing instance:

1. Have every user export a backup in **Settings** on the old instance.
2. Sign up on the new deployment and import that backup.

Passkeys cannot move because they are bound to the old hostname. Each user makes a new one.
