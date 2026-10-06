/* The serverless store's db.json diff (store-supabase.js). What it must get right is the part a
 * whole-file rewrite never had to: two function instances saving the same profile at once. Each
 * sends only the fields it changed, so neither undoes the other — above all, a stale copy must
 * never carry an old session version back over "sign out everywhere". */
import test from 'node:test';
import assert from 'node:assert/strict';
import { diffDb, dbFromRows, createSupabaseStore, throttleDeltas, isConflict } from '../store-supabase.js';

const empty = () => ({ users: [], creds: [], subs: [], invites: [], deviceLinks: [] });

test('a new entry is put whole, a removed one deleted', () => {
  const base = { ...empty(), users: [{ id: 'a', name: 'A' }] };
  const db = { ...empty(), users: [{ id: 'b', name: 'B' }] };
  assert.deepEqual(diffDb(base, db), [
    { op: 'put', c: 'users', k: 'b', data: { id: 'b', name: 'B' } },
    { op: 'del', c: 'users', k: 'a' }
  ]);
});

test('a changed entry sends only the fields that changed', () => {
  const base = { ...empty(), users: [{ id: 'a', name: 'A', sv: 1, lastPull: 5 }] };
  const db = { ...empty(), users: [{ id: 'a', name: 'A', sv: 1, lastPull: 9 }] };
  assert.deepEqual(diffDb(base, db), [{ op: 'patch', c: 'users', k: 'a', set: { lastPull: 9 }, unset: [] }]);
});

test('a field removed (or set to undefined) is unset, not sent', () => {
  const base = { ...empty(), users: [{ id: 'a', pwReset: { h: 'x' }, pw: { h: 'y' } }] };
  const db = { ...empty(), users: [{ id: 'a', pw: undefined }] };
  const [op] = diffDb(base, db);
  assert.deepEqual(op.set, {});
  assert.deepEqual(op.unset.sort(), ['pw', 'pwReset']);
});

test('nothing changed, nothing sent', () => {
  const db = { ...empty(), users: [{ id: 'a', n: [1, 2] }], subs: [{ endpoint: 'https://x', userId: 'a' }], other: { v: 1 } };
  assert.deepEqual(diffDb(JSON.parse(JSON.stringify(db)), db), []);
});

test('a stale instance noting a pull cannot undo a session-version bump', () => {
  // Both instances loaded sv 0. B bumps it; A only notes a pull. A's patch leaves sv alone.
  const loaded = { ...empty(), users: [{ id: 'a', sv: 0 }] };
  const a = { ...empty(), users: [{ id: 'a', sv: 0, lastPull: 1 }] };
  const ops = diffDb(loaded, a);
  assert.deepEqual(ops, [{ op: 'patch', c: 'users', k: 'a', set: { lastPull: 1 }, unset: [] }]);
});

test('lists are keyed by their natural id; other keys are kept whole under _meta', () => {
  const db = {
    ...empty(),
    subs: [{ endpoint: 'https://push/1', userId: 'a' }],
    invites: [{ code: 'C0DE' }],
    deviceLinks: [{ h: 'hash', userId: 'a' }],
    futureThing: { x: 1 }
  };
  assert.deepEqual(diffDb(empty(), db).map(o => [o.op, o.c, o.k]), [
    ['put', 'subs', 'https://push/1'], ['put', 'invites', 'C0DE'], ['put', 'deviceLinks', 'hash'],
    ['put', '_meta', 'futureThing']
  ]);
  assert.deepEqual(diffDb(db, { ...db, futureThing: undefined }).at(-1), { op: 'del', c: '_meta', k: 'futureThing' });
});

test('rows rebuild db.json in their stored order', () => {
  const db = dbFromRows([
    { coll: 'users', key: 'b', data: { id: 'b' } },
    { coll: 'users', key: 'a', data: { id: 'a' } },
    { coll: '_meta', key: 'futureThing', data: 1 },
    { coll: 'unknown', key: 'z', data: {} }
  ]);
  assert.deepEqual(db.users.map(u => u.id), ['b', 'a']);
  assert.equal(db.futureThing, 1);
  assert.deepEqual(db.creds, []);
  assert.equal('unknown' in db, false);
});

test('takeDiff fixes the operations at the moment of the save', async () => {
  const rows = [{ coll: 'users', key: 'a', data: { id: 'a', sv: 0 } }];
  const store = createSupabaseStore({
    url: 'https://example.supabase.co', key: 'k',
    fetch: async () => new Response(JSON.stringify(rows), { status: 200 })
  });
  const db = await store.loadDb();
  db.users[0].sv = 1;
  const first = store.takeDiff(db);
  db.users[0].lastPull = 7;          // changed after the save — belongs to the next one
  assert.deepEqual(first, [{ op: 'patch', c: 'users', k: 'a', set: { sv: 1 }, unset: [], expect: { sv: 0 } }]);
  assert.deepEqual(store.takeDiff(db), [{ op: 'patch', c: 'users', k: 'a', set: { lastPull: 7 }, unset: [] }]);
});

test('every request carries the service key, and a failure is an error with the status', async () => {
  const seen = [];
  const store = createSupabaseStore({
    url: 'https://example.supabase.co/', key: 'svc',
    fetch: async (u, init) => { seen.push([u, init.headers]); return new Response('{"message":"nope"}', { status: 401 }); }
  });
  await assert.rejects(store.readState('u1'), /401/);
  assert.equal(seen[0][0], 'https://example.supabase.co/rest/v1/opengym_state?select=data&uid=eq.u1');
  assert.equal(seen[0][1].apikey, 'svc');
  assert.equal(seen[0][1].Authorization, 'Bearer svc');
});

test('what must happen once carries its guard', () => {
  const base = {
    ...empty(),
    users: [{ id: 'a', sv: 2 }],
    invites: [{ code: 'C1' }, { code: 'C2' }],
    deviceLinks: [{ h: 'L', userId: 'a' }]
  };
  const db = {
    ...empty(),
    users: [{ id: 'a', sv: 3 }],
    invites: [{ code: 'C1', usedBy: 'b', usedAt: 't' }],
    deviceLinks: []
  };
  const ops = diffDb(base, db);
  assert.deepEqual(ops.find(o => o.c === 'users').expect, { sv: 2 });
  assert.deepEqual(ops.find(o => o.k === 'C1').expect, { usedBy: null });
  assert.equal(ops.find(o => o.k === 'C2').must, true);
  assert.equal(ops.find(o => o.c === 'deviceLinks').must, true);
  // An unguarded field gets no guard, so bookkeeping never collides.
  assert.equal(diffDb({ ...empty(), users: [{ id: 'a' }] }, { ...empty(), users: [{ id: 'a', lastPull: 1 }] })[0].expect, undefined);
  assert.equal(isConflict(new Error('supabase POST /rpc/opengym_db_apply: 400 {"message":"opengym_conflict: users a changed"}')), true);
  assert.equal(isConflict(new Error('timeout')), false);
});

test('throttle changes travel as deltas, so concurrent counts add up', () => {
  const before = [['acct:a', { n: 4, until: 0, last: 100 }], ['w', { start: 10, count: 3 }], ['gone', { n: 1, until: 0, last: 1 }]];
  const after = [['acct:a', { n: 5, until: 0, last: 200 }], ['w', { start: 10, count: 4 }], ['new', { n: 1, until: 0, last: 200 }]];
  assert.deepEqual(throttleDeltas('acct', before, after), [
    { lim: 'acct', key: 'acct:a', op: 'add', dn: 1, until: 0, last: 200, e: { n: 5, until: 0, last: 200 } },
    { lim: 'acct', key: 'w', op: 'add', dc: 1, e: { start: 10, count: 4 } },
    { lim: 'acct', key: 'new', op: 'add', dn: 1, until: 0, last: 200, e: { n: 1, until: 0, last: 200 } },
    { lim: 'acct', key: 'gone', op: 'del' }
  ]);
  // A new window, or a count that was forgotten and began again, is sent whole.
  assert.equal(throttleDeltas('burst', [['w', { start: 1, count: 9 }]], [['w', { start: 99, count: 1 }]])[0].op, 'set');
  assert.equal(throttleDeltas('acct', [['k', { n: 9, until: 0, last: 5 }]], [['k', { n: 1, until: 0, last: 900 }]])[0].op, 'set');
  // Unchanged keys send nothing.
  assert.deepEqual(throttleDeltas('acct', before, before), []);
});
