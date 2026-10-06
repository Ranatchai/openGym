/* Storage for the serverless deployment (Vercel + Supabase, docs/SELF_HOSTING_VERCEL.md).
 *
 * A self-hosted instance is one long-running process with a disk: db.json in memory, state
 * files next to it, challenges and timers in Maps. A function has neither — any number of
 * instances may be answering at once and each forgets everything between invocations — so
 * every one of those moves into Postgres (supabase/migrations). This module is the only place
 * that talks to it, over PostgREST with the service-role key, so the API keeps its two
 * dependencies: fetch is built in.
 *
 * db.json keeps its shape in memory. What changes is how it is saved: `snapshot()` remembers
 * what was loaded, and `diff()` turns the difference into per-entry, per-field operations
 * (opengym_db_apply), never a whole-file rewrite. Two instances that changed different fields
 * of one profile — one noting a pull, the other bumping the session version for "sign out
 * everywhere" — then both land, where a rewrite would let the later one undo the earlier. */

// How each list in db.json is keyed. Anything else on db is kept whole under `_meta`.
export const COLLECTIONS = { users: 'id', creds: 'id', subs: 'endpoint', invites: 'code', deviceLinks: 'h' };
const META = '_meta';
// What must happen once, however many instances race for it. A change to one of these fields
// carries the value it was changed from (`expect`), and the database refuses the whole save when
// another instance changed it first: an invite is used once, a session version is not bumped
// over a bump. Removing a device link or an invite requires it to still be there (`must`), so one
// link redeemed on two instances at once lets only one of them through.
const GUARDED = { users: ['sv'], invites: ['usedBy', 'revoked'] };
const MUST_EXIST_ON_DELETE = new Set(['deviceLinks', 'invites']);

const clone = v => (v === undefined ? undefined : JSON.parse(JSON.stringify(v)));
const same = (a, b) => JSON.stringify(a) === JSON.stringify(b);

/** The entries of one list, by key. A later duplicate wins, as a lookup by key would see it. */
function byKey(list, k) {
  const m = new Map();
  for (const e of Array.isArray(list) ? list : []) {
    if (e && typeof e === 'object' && e[k] != null) m.set(String(e[k]), e);
  }
  return m;
}

/** The operations that turn `base` into `db`. Pure — exported for the tests. */
export function diffDb(base, db) {
  const ops = [];
  for (const [coll, k] of Object.entries(COLLECTIONS)) {
    const before = byKey(base?.[coll], k), after = byKey(db?.[coll], k);
    for (const [key, e] of after) {
      const old = before.get(key);
      if (!old) { ops.push({ op: 'put', c: coll, k: key, data: e }); continue; }
      const set = {}, unset = [];
      for (const f of Object.keys(e)) if (!same(e[f], old[f])) set[f] = e[f];
      for (const f of Object.keys(old)) if (!(f in e) || e[f] === undefined) unset.push(f);
      for (const f of unset) delete set[f];
      if (!Object.keys(set).length && !unset.length) continue;
      const op = { op: 'patch', c: coll, k: key, set, unset };
      const guarded = (GUARDED[coll] || []).filter(f => f in set || unset.includes(f));
      if (guarded.length) op.expect = Object.fromEntries(guarded.map(f => [f, old[f] ?? null]));
      ops.push(op);
    }
    for (const key of before.keys()) {
      if (!after.has(key)) ops.push({ op: 'del', c: coll, k: key, ...(MUST_EXIST_ON_DELETE.has(coll) ? { must: true } : {}) });
    }
  }
  for (const f of new Set([...Object.keys(base || {}), ...Object.keys(db || {})])) {
    if (f in COLLECTIONS) continue;
    if (db?.[f] === undefined) { if (base?.[f] !== undefined) ops.push({ op: 'del', c: META, k: f }); }
    else if (!same(db[f], base?.[f])) ops.push({ op: 'put', c: META, k: f, data: db[f] });
  }
  return ops;
}

/** db.json rebuilt from its rows (ordered by insertion, as the arrays were). Pure. */
export function dbFromRows(rows) {
  const db = { users: [], creds: [], subs: [], invites: [], deviceLinks: [] };
  for (const r of rows) {
    if (r.coll === META) db[r.key] = r.data;
    else if (r.coll in COLLECTIONS) db[r.coll].push(r.data);
  }
  return db;
}

export class StoreError extends Error {}
/** A guarded save lost a race (opengym_db_apply): the request is answered 409, not 500. */
export const isConflict = e => /opengym_conflict/.test(e?.message || '');
// A hung request must not hold the instance's request queue (server.js, serialized).
const TIMEOUT_MS = 10000;

export function createSupabaseStore({ url, key, fetch: f = globalThis.fetch, now = Date.now }) {
  if (!url || !key) throw new Error('SUPABASE_URL and SUPABASE_SERVICE_ROLE_KEY are both required');
  const base = url.replace(/\/+$/, '') + '/rest/v1';
  const q = encodeURIComponent;

  async function rest(method, path, { body, prefer, headers } = {}) {
    const res = await f(base + path, {
      method,
      headers: {
        apikey: key, Authorization: 'Bearer ' + key,
        ...(body !== undefined ? { 'Content-Type': 'application/json' } : {}),
        ...(prefer ? { Prefer: prefer } : {}),
        ...headers
      },
      body: body !== undefined ? JSON.stringify(body) : undefined,
      signal: AbortSignal.timeout(TIMEOUT_MS)
    });
    const text = await res.text();
    if (!res.ok) throw new StoreError(`supabase ${method} ${path.split('?')[0]}: ${res.status} ${text.slice(0, 200)}`);
    return { data: text ? JSON.parse(text) : null, headers: res.headers };
  }
  const rpc = async (fn, args) => (await rest('POST', '/rpc/' + fn, { body: args })).data;

  /* ---------- db.json ---------- */
  let baseline = null;
  async function loadDb() {
    const { data } = await rest('GET', '/opengym_rows?select=coll,key,data&order=seq.asc');
    const db = dbFromRows(data || []);
    baseline = clone(db);
    return db;
  }
  /** The operations needed to save `db`, taken now: the caller may go on changing it. */
  function takeDiff(db) {
    const ops = diffDb(baseline, db);
    baseline = clone(db);
    return ops;
  }
  async function applyDb(ops) { if (ops.length) await rpc('opengym_db_apply', { ops }); }

  /* ---------- per-profile state ---------- */
  async function readState(uid) {
    const { data } = await rest('GET', `/opengym_state?select=data&uid=eq.${q(uid)}`);
    return data?.[0]?.data ?? null;
  }
  async function readRev(uid) {
    const { data } = await rest('GET', `/opengym_state?select=rev&uid=eq.${q(uid)}`);
    return data?.[0]?.rev || 0;
  }
  /** { ok:true, rev } or { ok:false, rev, state } — the latter when `expect` is not current. */
  const writeState = (uid, expect, state) => rpc('opengym_state_write', { p_uid: uid, p_expect: expect, p_data: state });
  async function deleteState(uid) { await rest('DELETE', `/opengym_state?uid=eq.${q(uid)}`); }
  /** Whole documents of these profiles. A POST, since a list in the URL outgrows its limit. */
  async function readStates(uids) {
    if (!uids.length) return new Map();
    const data = await rpc('opengym_states', { p_uids: uids });
    return new Map((data || []).map(r => [r.uid, r.data]));
  }
  /** The reminder settings of those of these profiles that have one on — and nothing else. */
  async function readReminders(uids) {
    if (!uids.length) return new Map();
    const data = await rpc('opengym_reminders', { p_uids: uids });
    return new Map((data || []).map(r => [r.uid, r.reminder]));
  }
  /** uid -> { workouts, lastWorkout, ts } for the admin list, counted in the database. */
  async function stateSummaries() {
    const data = await rpc('opengym_state_summaries', {});
    return new Map((data || []).map(r => [r.uid, { workouts: r.workouts || 0, lastWorkout: r.last_workout || null, ts: r.ts || null }]));
  }

  /* ---------- short-lived entries ---------- */
  const eph = {
    async put(ns, k, data, ttlMs) {
      await rest('POST', '/opengym_eph', {
        body: { ns, key: k, data, exp: now() + ttlMs }, prefer: 'resolution=merge-duplicates,return=minimal'
      });
    },
    /** Removes and returns one entry, or null when it is missing or expired. One-shot under any
     *  number of instances: of two takers only one gets the deleted row back. */
    async take(ns, k) {
      const { data } = await rest('DELETE', `/opengym_eph?ns=eq.${q(ns)}&key=eq.${q(k)}`, { prefer: 'return=representation' });
      const r = data?.[0];
      return r && r.exp > now() ? r.data : null;
    },
    async has(ns, k) {
      const { data } = await rest('GET', `/opengym_eph?select=key&ns=eq.${q(ns)}&key=eq.${q(k)}&exp=gt.${now()}`);
      return !!data?.length;
    },
    async del(ns, k) { await rest('DELETE', `/opengym_eph?ns=eq.${q(ns)}&key=eq.${q(k)}`); },
    async delByUid(ns, uid) { await rest('DELETE', `/opengym_eph?ns=eq.${q(ns)}&data->>uid=eq.${q(uid)}`); },
    async list(ns) {
      const { data } = await rest('GET', `/opengym_eph?select=key,data&ns=eq.${q(ns)}&exp=gt.${now()}`);
      return new Map((data || []).map(r => [r.key, r.data]));
    },
    async sweep() { await rest('DELETE', `/opengym_eph?exp=lt.${now()}`); }
  };

  /* ---------- key/value: secrets, throttle counters ---------- */
  const kv = {
    async get(k) {
      const { data } = await rest('GET', `/opengym_kv?select=data&key=eq.${q(k)}`);
      return data?.[0]?.data ?? null;
    },
    async set(k, data) {
      await rest('POST', '/opengym_kv', { body: { key: k, data }, prefer: 'resolution=merge-duplicates,return=minimal' });
    },
    /** The stored value, or `make()` stored first when there is none. Of two instances booting at
     *  once, both end up with whichever was written first. */
    async getOrCreate(k, make) {
      const have = await kv.get(k);
      if (have != null) return have;
      await rest('POST', '/opengym_kv', { body: { key: k, data: make() }, prefer: 'resolution=ignore-duplicates,return=minimal' });
      return kv.get(k);
    }
  };

  /* ---------- audit log ---------- */
  const audit = {
    async append(rec) { await rest('POST', '/opengym_audit', { body: { ts: rec.ts, ev: rec.ev, ok: rec.ok, rec }, prefer: 'return=minimal' }); },
    /** Newest first. `cut` drops what is older than retention, `cat` is the dashboard's filter. */
    async page({ limit, before, cat, cut, max }) {
      let filt = '';
      if (cut) filt += `&ts=gte.${cut}`;
      if (cat === 'fail') filt += '&ok=is.false';
      else if (cat) filt += `&ev=like.${q(cat.replace(/[%_*]/g, '') + '.*')}`;
      // Retention by count is the newest `max` rows of the whole log, filter or not.
      if (max) {
        const { data } = await rest('GET', `/opengym_audit?select=id&order=id.desc&offset=${max}&limit=1`);
        if (data?.[0]) filt += `&id=gt.${data[0].id}`;
      }
      const page = Number.isFinite(before) ? `&id=lt.${before}` : '';
      const { data, headers } = await rest('GET', `/opengym_audit?select=id,rec&order=id.desc&limit=${limit}${filt}${page}`,
        { prefer: 'count=exact' });
      // The total is of the filtered log, without the page cursor — as the file-backed route counts.
      let total = 0;
      if (page) {
        const r = await rest('GET', `/opengym_audit?select=id&limit=1${filt}`, { prefer: 'count=exact' });
        total = +(r.headers.get('content-range') || '').split('/')[1] || 0;
      } else total = +(headers.get('content-range') || '').split('/')[1] || 0;
      return { events: (data || []).map(r => ({ ...r.rec, id: r.id })), total };
    },
    async clear() { await rest('DELETE', '/opengym_audit?id=gte.0'); },
    compact: (max, cut) => rpc('opengym_audit_compact', { p_max: max, p_cut: cut })
  };

  /* ---------- rest timers ---------- */
  const timers = {
    async schedule(k, uid, fireAt, payload) {
      await rest('POST', '/opengym_timers', {
        body: { key: k, uid, fire_at: fireAt, payload }, prefer: 'resolution=merge-duplicates,return=minimal'
      });
    },
    async cancel(k) { await rest('DELETE', `/opengym_timers?key=eq.${q(k)}`); },
    async cancelUser(uid) { await rest('DELETE', `/opengym_timers?uid=eq.${q(uid)}`); },
    claimDue: async () => (await rpc('opengym_timers_claim', {})) || []
  };

  /* ---------- sign-in throttle ---------- */
  const throttle = {
    /** { burst: [[key, e]…], addr: […], acct: […] } as rate-limit.js load() takes them. */
    async load() {
      const { data } = await rest('GET', '/opengym_throttle?select=lim,key,e');
      const out = { burst: [], addr: [], acct: [] };
      for (const r of data || []) if (out[r.lim]) out[r.lim].push([r.key, r.e]);
      return out;
    },
    apply: async ops => { if (ops.length) await rpc('opengym_throttle_apply', { p_ops: ops }); }
  };

  return {
    loadDb, takeDiff, applyDb, readState, readRev, writeState, deleteState, readStates, readReminders,
    stateSummaries, eph, kv, audit, timers, throttle
  };
}

/** What one request did to one limiter, as deltas for opengym_throttle_apply. `before` and
 *  `after` are rate-limit.js dump()s. A count that grew is sent as the growth, so instances
 *  counting the same key at the same moment add up; one that started over is sent whole. */
export function throttleDeltas(lim, before, after) {
  const was = new Map(before), ops = [];
  for (const [key, e] of after) {
    const old = was.get(key);
    was.delete(key);
    if (old && JSON.stringify(old) === JSON.stringify(e)) continue;
    if ('count' in e) {                                    // a window: { start, count }
      if (old && old.start === e.start) ops.push({ lim, key, op: 'add', dc: e.count - old.count, e });
      else ops.push({ lim, key, op: 'set', e });
    } else if (old && e.n >= old.n - 1 && e.last >= old.last) {
      // A backoff that went on counting (an undone attempt can take one back).
      ops.push({ lim, key, op: 'add', dn: e.n - old.n, until: e.until, last: e.last, e });
    } else if (old) ops.push({ lim, key, op: 'set', e });  // forgotten and begun again
    else ops.push({ lim, key, op: 'add', dn: e.n, until: e.until, last: e.last, e });
  }
  for (const key of was.keys()) ops.push({ lim, key, op: 'del' });
  return ops;
}
