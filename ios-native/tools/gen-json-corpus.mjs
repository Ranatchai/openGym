process.env.TZ = 'UTC'

import fs from 'node:fs'
import path from 'node:path'
import { pathToFileURL } from 'node:url'
import { registerHooks } from 'node:module'

const FIXED_NOW = Date.UTC(2026, 6, 27, 12, 0, 0)
const RealDate = Date
class FixedDate extends RealDate {
  constructor(...args) { if (args.length) super(...args); else super(FIXED_NOW) }
  static now() { return FIXED_NOW }
}
globalThis.Date = FixedDate

let rngState = 0
const seed = n => { rngState = n >>> 0 }
const rng = () => {
  rngState = (rngState + 0x6d2b79f5) >>> 0
  let t = rngState
  t = Math.imul(t ^ (t >>> 15), t | 1)
  t ^= t + Math.imul(t ^ (t >>> 7), t | 61)
  return ((t ^ (t >>> 14)) >>> 0) / 4294967296
}
Math.random = rng
const int = n => Math.floor(rng() * n)
const pick = xs => xs[int(xs.length)]

const KEYS = [
  '"0"', '"7"', '"20"', '"4294967294"', '"01"', '"1.0"', '"-1"', '"4294967295"', '"00"', '"1e3"',
  '"id"', '"name"', '"w"', '"r"', '"done"', '"_ts"', '"sets"', '"entries"', '"routineIds"', '"kg"',
  '"สควอท"', '"น้ำหนัก"', '"💪"', '"🏋️"', '""', '"a b"',
  String.raw`"\u0032\u0030"`, String.raw`"x\"y"`, String.raw`"tab\there"`, String.raw`"\u00e9t\u00e9"`,
]

const STRING_PIECES = [
  'abc', 'Bench Press', ' ', 'สวัสดี', 'ยกน้ำหนัก', '💪', '😀', '🏋️‍♀️',
  String.raw`\ud83d\ude00`, String.raw`\uD83C\uDFCB`, String.raw`\ud83d`, String.raw`\udc00`, String.raw`\uDBFF`,
  String.raw`\n`, String.raw`\t`, String.raw`\r`, String.raw`\b`, String.raw`\f`, String.raw`\"`, String.raw`\\`, String.raw`\/`,
  String.raw`\u0000`, String.raw`\u001f`, String.raw`\u0001`, String.raw`\u007F`, String.raw`\u00e9`, String.raw`\u0e01`,
  '\u2028', '\u2029', '\u007f', '</script>', 'é',
]

const REPO = path.resolve(import.meta.dirname, '../..')
const LIB = path.join(REPO, 'frontend/src/lib')

const flag = name => {
  const i = process.argv.indexOf(name)
  if (i < 0) return null
  const value = process.argv[i + 1]
  if (!value) throw new Error(`${name} needs a path`)
  return value
}
const largePath = flag('--large')
const OUT = flag('--out') ?? path.join(REPO, 'ios-native/OpenGymCore/Tests/OpenGymCoreTests/Fixtures/json-corpus')
const SYNC_MERGE_TEST = flag('--sync-merge-test') ?? path.join(LIB, 'sync-merge.test.js')

const DEF = {
  unit: 'kg', restSec: 90, restPauseSec: 15, sound: true, soundOnSilent: false, timerFlash: false, timedSetOvertime: false, keepAwake: true, lang: 'en',
  theme: 'light', accent: 'orchid', body: 'male', targetW: null,
  bodyweight: [], routines: [], week: {}, dayPlan: {},
  exWeights: {}, workouts: [], active: null, customEx: [], gifSize: 'full',
  heatmapMetric: 'time',
  workoutView: 'cards',
  wc: { steppers: true, setShortcuts: false, pairButtons: false, exerciseButtons: false },
  reminder: { on: false, time: '08:00', tz: null }, effort: null, autoBackup: false,
  equipProfiles: [], activeEquipId: null, equipFilterOn: false,
  exNotes: {},
  favEx: [],
  weekStart: 1,
  wdec: 1,
  speedUnit: null,
  barWeights: {},
  plates: {},
  loadKind: {},
  gymCards: [],
  lastGymCardId: null,
  checkIn: true,
  showWeightCard: true,
  weighIn: true,
  startFrom: 'plan',
  enParens: {},
  enOnly: {},
  logRef: 'last',
  balanceTemplate: 'poliquin', balanceOverrides: {},
}

const files = new Map()
const put = (rel, text) => files.set(rel, Buffer.from(text, 'utf8'))
const canon = text => JSON.stringify(JSON.parse(text))
const counts = { cases: 0, random: 0, edits: 0, malformed: 0 }

const addCase = (name, input) => {
  put(`cases/${name}/input.json`, input)
  put(`cases/${name}/expected.json`, canon(input))
  counts.cases++
}

seed(1)
const { buildDemoState } = await import(pathToFileURL(path.join(LIB, 'demoSeed.js')).href)
const demo = buildDemoState()
const demoState = { ...structuredClone(DEF), ...demo, _ts: 1753617600000, _rev: 7, langAuto: true }

addCase('demo', JSON.stringify(demoState))
addCase('demo-pretty', JSON.stringify(demoState, null, 2))
addCase('def', JSON.stringify(DEF))

const media = { hash: 'a3f1c9e07b5d4e2f8a6b1c0d9e8f7a6b5c4d3e2f1a0b9c8d7e6f5a4b3c2d1e0f', kind: 'image', mime: 'image/jpeg', w: 1080, h: 1440, bytes: 182344, poster: null }
const kitchenSink = {
  ...structuredClone(DEF),
  unit: 'kg', restSec: 120, lang: 'th', theme: 'dark', accent: 'coral', body: 'female', targetW: 72.5,
  bodyweight: [{ d: '2026-07-20', w: 74.1, t: 1784539800000 }, { d: '2026-07-27', w: 73.6, t: 1785144600000 }],
  routines: [
    {
      id: 'r1', name: 'วันอก 💪 Push', emoji: '🏋️', prog: 'double', excludeFromProgression: false, _ts: 1785100000000,
      ex: [
        { id: '0025', sets: 4, reps: 8, weight: 80, repsMin: 6, repsMax: 10, inc: 2.5, prog: 'linear', warmupSets: 2, sg: 'A', note: 'แตะอก', media, caps: { w: 140 } },
        { id: '0047', sets: 3, reps: 10, weight: 22.5, sg: 'A', side: true, deloadFactor: 0.9, intensifier: { type: 'dropset', drops: 2, pct: 0.8 } },
        { id: '1185', sets: 3, reps: 0, weight: 0, sec: 45, mode: 'time', bodyweight: true, intensifier: { type: 'restpause', clusters: 3, restSec: 15 } },
        { id: '3341', sets: 1, reps: 0, weight: 0, min: 20, speed: 9.5, mode: 'cardio' },
      ],
    },
    { id: 'r2', name: 'Pull', emoji: 'barbell', ex: [{ id: '0027', sets: 3, reps: 5, weight: 100.5, mode: 'reps' }] },
    { id: 'r3', name: 'ขา', emoji: 'legs', excludeFromProgression: true, ex: [] },
  ],
  week: '__WEEK__',
  dayPlan: { '2026-07-28': 'r1', '2026-07-29': 'rest', '2026-07-30': 'r2' },
  exWeights: { '0025': { w: 80, d: '2026-07-27' }, '0027': { w: 100.5, d: '2026-07-25' } },
  workouts: [
    {
      id: 'w1', d: '2026-07-27', start: 1785139200000, end: 1785143100000, routineIds: ['r1'], routineId: 'r1', name: 'วันอก 💪 Push', bw: 73.6,
      entries: [
        {
          id: '0025', topW: 82.5, target: 80, rid: 'r1', planned: true, sg: 'A', muscleSnapshot: { chest: 1, triceps: 0.5 }, note: 'หนักไป', notePin: true,
          sets: [
            { w: 40, r: 10, done: true, phase: 'warmup' },
            { w: 60, r: 5, done: true, warmup: true },
            { w: 82.5, r: 8, done: true, rir: 2, phase: 'work' },
            { w: 80, r: 8, done: true, rpe: 8.5, type: 'dropset', drops: [{ w: 60, r: 6, done: true }, { w: 40, r: 8, done: false }] },
            { w: 70, r: 6, done: true, type: 'restpause', clusters: [{ r: 3, done: true }, { r: 2, done: true }] },
          ],
        },
        {
          id: '0047', topW: 22.5, target: null, noProg: true, sg: 'A',
          sets: [{ w: 22.5, r: 10, done: true, sides: { L: { w: 22.5, r: 10, done: true, rir: 1 }, R: { w: 22.5, r: 9, done: true, rpe: 9, type: 'dropset', drops: [{ w: 15, r: 5, done: true }] } } }],
        },
        { id: '1185', topW: null, target: null, sets: [{ sec: 45, w: 0, done: true }, { sec: 40, w: 10, done: false }] },
        { id: '3341', topW: null, target: null, sets: [{ min: 20, speed: 9.5, done: true }] },
      ],
      prs: ['0025'], vol: 3460, media: [media], _ts: 1785143200000, excludeFromProgression: false, note: 'รู้สึกดี 😀',
    },
  ],
  active: {
    id: 'a1', d: '2026-07-26', start: 1785052800000, routineIds: ['r2'], name: 'Pull', bw: 73.8, cur: 0, workoutView: 'list',
    entries: [{ id: '0027', rid: 'r2', sg: null, noProg: false, note: '', target: 100.5, plan: { sets: 3, reps: 5 }, planned: true, carried: false, sets: [{ w: 100.5, r: 5, done: false }] }],
    backfill: { durationMin: 55, replaceId: null },
    editingWorkoutId: null, customName: 'ดึง', note: 'backfill',
  },
  customEx: [{
    id: 'cx1', n: 'ท่าพิเศษ', bp: 'chest', desc: 'Custom press', tg: 'pectorals', sm: ['triceps'], muscleGroups: ['chest'], primaries: ['chest'], secondaries: ['triceps'], eq: 'dumbbell', custom: true,
    media, url: 'https://example.com/v?id=1&t=2', _ts: 1785000000000,
  }],
  gifSize: 'small', heatmapMetric: 'volume', workoutView: 'compact',
  wc: { steppers: false, setShortcuts: true, pairButtons: true, exerciseButtons: false },
  reminder: { on: true, time: '06:30', tz: 'Asia/Bangkok' }, effort: 'rir', autoBackup: true,
  equipProfiles: [{ id: 'e1', name: 'Home', equipment: ['dumbbell', 'body weight'] }], activeEquipId: 'e1', equipFilterOn: true,
  exNotes: { '0025': 'seat 4, pin 7', '0047': '' },
  favEx: ['0025', 'cx1'],
  weekStart: 0, wdec: 2, speedUnit: 'kmh',
  barWeights: { '0025': 20, '0047': 0 },
  plates: '__PLATES__',
  loadKind: { '0025': { kind: 'pairs', _ts: 3 }, '0027': { kind: null, _ts: 4 } },
  gymCards: [{ id: 'g1', label: 'ยิม', value: '0123456789', fmt: 'qrcode' }], lastGymCardId: 'g1',
  checkIn: false, showWeightCard: false, weighIn: false, startFrom: 'last',
  enParens: { th: false, de: true }, enOnly: { de: true },
  logRef: 'best',
  balanceTemplate: 'poliquin', balanceOverrides: { 'poliquin:bench': { id: '0025', _ts: 5 }, 'poliquin:row': { id: null, _ts: 6 } },
  _ts: 1785143300000, _rev: 42, langAuto: false,
  unitSet: { at: 1785000000000, convert: true },
  resetAt: 1780000000000,
  resetIds: {
    workouts: ['w0'], routines: ['r0'], customEx: ['cx0'], bodyweight: ['2026-01-01'], gymCards: ['g0'], equipProfiles: ['e0'],
    favEx: ['0001'], exNotes: ['0002'], barWeights: ['0003'], balanceOverrides: ['poliquin:squat'], loadKind: ['0004'], plates: ['lb'],
  },
  coach: { consent: null, profile: null, cadence: 'off', lastReview: null, log: [], snapshots: [], chat: [], timings: [] },
  showRir: true,
}
const kitchenSinkText = JSON.stringify(kitchenSink)
  .replace('"__WEEK__"', '{"3":["r2","r3"],"1":"r1","5":[],"0":"r2"}')
  .replace('"__PLATES__"', '{"kg":{"_ts":1,"20":2,"10":2,"1.25":1},"lb":{"_ts":2,"45":2}}')
addCase('kitchen-sink', kitchenSinkText)

addCase('week-legacy', '{"unit":"kg","week":{"6":["r3"],"2":"r1","0":[],"4":["r1","r2"],"1":"r2","5":"r3","3":["r2"]},"dayPlan":{"2026-07-29":"rest"}}')

const NUMBERS = '0.1, 1e-7, 1e21, 1e20, -0, 5e-324, 1.7976931348623157e308, 1784139960000, 82.4, 1e16, 1e15, 9007199254740993, 1.5e-6, 0.000001, 123456.789e3, 2.5e-5, 1e300, 100, 0.5, 4.35, 1e-5, 0.00001234, 2e-7, 123e-20, -1.5, 1E5, 1e+5, 0.1e1, 12345678901234567890, 4294967295, 4294967294, 0.30000000000000004, 1e-308, 2.2250738585072014e-308, 2.225073858507201e-308'
addCase('numbers', '[' + NUMBERS.split(', ').join(',') + ']')

const controls = Array.from({ length: 32 }, (_, i) => '\\u00' + i.toString(16).padStart(2, '0')).join('')
const stringMembers = [
  ['thai', '"สวัสดีครับ ยกน้ำหนัก"'],
  ['emoji', '"💪🏋️‍♀️"'],
  ['pair', String.raw`"\ud83d\ude00"`],
  ['pairUpper', String.raw`"\uD83D\uDE00"`],
  ['loneHigh', String.raw`"\ud83d"`],
  ['loneLow', String.raw`"\ude00"`],
  ['loneHighThenChar', String.raw`"\ud83dA"`],
  ['loneLowThenChar', String.raw`"x\ude00b"`],
  ['separators', '"a\u2028b\u2029c"'],
  ['controls', '"' + controls + '"'],
  ['shortEscapes', String.raw`"\b\f\n\r\t"`],
  ['del', '"a\u007fb"'],
  ['solidus', String.raw`"a\/b"`],
  ['quoteBackslash', String.raw`"\"\\"`],
  ['script', '"</script>"'],
  ['empty', '""'],
  ['', '"empty key"'],
]
addCase('strings', '{' + stringMembers.map(([k, v]) => `"${k}":${v}`).join(',') + '}')

const keyOrder = '"b":1,"20":2,"3":3,"a":4,"01":5,"0":6,"4294967295":7,"4294967294":8,"-1":9,"1.0":10,"":11'
addCase('key-order', `{${keyOrder},"nested":{${keyOrder}}}`)
addCase('duplicate-keys', '{"a":1,"b":2,"a":3,"1":4,"c":5,"1":6}')
addCase('nfc-key-raw', '{"é":1,"é":2}')
addCase('nfc-key-escaped', String.raw`{"\u00e9":1,"e\u0301":2}`)
addCase('nfc-key-angstrom', '{"Å":1,"Å":2,"Å":3}')
addCase('nfc-key-indexed', '{' + Array.from({ length: 20 }, (_, i) => `"k${i}":${i}`).join(',') + ',"é":1,"é":2}')
addCase('surrogate-in-key', String.raw`{"\ud800":1,"\ud800":2,"\udc00":3,"\ud83d\ude00":4,"\ud83d":5}`)

addCase('scalar-string', '"hello \\u00e9 ยก"')
addCase('scalar-number', '-1.50E+3')
addCase('scalar-true', 'true')
addCase('scalar-null', 'null')
addCase('empty-object', '{}')
addCase('empty-array', '[]')
addCase('nested-empty', '[{"a":{}},[[]],{"b":[],"c":{}}]')

addCase('whitespace', ' \r\n{\t"a" \n:\r\n[ 1 ,\t2.5e1\r\n, \t"x y"\n,\r\ntrue ,\tfalse\n, null ] \t,\r\n"b"\n:\t{ } ,\r\n"c" : [ ]\n}\r\n\t \n')

let deep = '1'
for (let i = 0; i < 200; i++) deep = i % 2 ? `{"k${i}":${deep}}` : `[${deep}]`
addCase('deep', deep)

seed(2)
const syncMergeInputs = await recordSyncMergeArgs()
syncMergeInputs.forEach((text, i) => addCase(`sync-merge-${String(i + 1).padStart(3, '0')}`, text))

seed(3)
const randomInputs = Array.from({ length: 500 }, genDoc)
put('random/inputs.ndjson', randomInputs.join('\n'))
put('random/expected.ndjson', randomInputs.map(canon).join('\n'))
counts.random = randomInputs.length

const withoutKey = (o, k) => { const c = { ...o }; delete c[k]; return c }
const twoRoutines = [
  { id: 'n1', name: 'Upper ⬆️', emoji: 'barbell', ex: [{ id: '0025', sets: 3, reps: 8, weight: 60 }] },
  { id: 'n2', name: 'ล่าง', emoji: 'legs', _ts: 1785143400000, ex: [] },
]
const extraWorkout = { id: 'wx', d: '2026-07-27', start: 1785139200000, end: 1785142800000, routineIds: [], routineId: null, name: 'Extra', bw: 82.1, entries: [{ id: '0025', sets: [{ w: 60.5, r: 8, done: true }], topW: 60.5 }], prs: [], vol: 484 }
const demoText = JSON.stringify(demoState)
const editCases = [
  ['restSec-existing', demoText, { restSec: 120 }],
  ['restSec-missing', JSON.stringify(withoutKey(demoState, 'restSec')), { restSec: 120 }],
  ['unit-existing', kitchenSinkText, { unit: 'lb' }],
  ['unit-missing', JSON.stringify(withoutKey(demoState, 'unit')), { unit: 'lb' }],
  ['routines-replace', demoText, { routines: twoRoutines }],
  ['workouts-append', demoText, { workouts: [...demoState.workouts, extraWorkout] }],
  ['all-four', demoText, { unit: 'lb', restSec: 60, routines: twoRoutines, workouts: [...demoState.workouts, extraWorkout] }],
]
for (const [name, input, edit] of editCases) {
  const S = JSON.parse(input)
  for (const [k, v] of Object.entries(edit)) S[k] = v
  put(`edits/${name}/input.json`, input)
  put(`edits/${name}/edit.json`, JSON.stringify(edit))
  put(`edits/${name}/expected.json`, JSON.stringify(S))
  counts.edits++
}

const malformed = {
  'trailing-comma-object': '{"a":1,}',
  'trailing-comma-array': '[1,2,]',
  'truncated-object': '{"a":1',
  'truncated-string': '{"a":"abc',
  'empty-file': '',
  'bom-prefix': '\ufeff{}',
  'single-quotes': "{'a':1}",
  'nan-literal': '[NaN]',
  'leading-zero': '[01]',
  'hex-number': '[0x1F]',
  'plus-sign': '[+1]',
  'bare-control-char-in-string': '["a\u0001b"]',
  'invalid-escape': String.raw`["\x41"]`,
  'trailing-garbage': '{} x',
  'unquoted-key': '{a:1}',
  'lone-value-after-root': '[1] 2',
  'dot-no-digits': '[1.]',
  'exponent-no-digits': '[1e]',
  'comment': '{"a":1 /* c */}',
}
for (const [name, text] of Object.entries(malformed)) {
  let threw = false
  try { JSON.parse(Buffer.from(text, 'utf8').toString('utf8')) } catch { threw = true }
  if (!threw) throw new Error(`malformed/${name} parses in Node`)
  put(`malformed/${name}.json`, text)
  counts.malformed++
}

fs.rmSync(OUT, { recursive: true, force: true })
let totalBytes = 0
for (const [rel, buf] of [...files].sort(([a], [b]) => (a < b ? -1 : 1))) {
  const abs = path.join(OUT, rel)
  fs.mkdirSync(path.dirname(abs), { recursive: true })
  fs.writeFileSync(abs, buf)
  totalBytes += buf.length
}

if (largePath) {
  seed(4)
  const text = buildLarge()
  fs.writeFileSync(largePath, text)
  console.log(`large: ${Buffer.byteLength(text)} bytes -> ${largePath}`)
}

console.log(`cases=${counts.cases} sync-merge=${syncMergeInputs.length} random=${counts.random} edits=${counts.edits} malformed=${counts.malformed} bytes=${totalBytes}`)

async function recordSyncMergeArgs() {
  const testUrl = pathToFileURL(SYNC_MERGE_TEST).href
  const testSrc = fs.readFileSync(new URL(testUrl), 'utf8')
  const libSpecs = [...testSrc.matchAll(/from '(\.\/[\w.-]+\.js)'/g)].map(m => m[1])
  const exportsOf = new Map()
  for (const spec of libSpecs) {
    const url = new URL(spec, testUrl).href
    exportsOf.set(url, Object.keys(await import(url)))
  }

  const seen = new Set()
  const recorded = []
  const record = arg => {
    if (!arg || typeof arg !== 'object') return
    let text
    try { text = JSON.stringify(arg) } catch { return }
    if (text === undefined || text.length < 40 || seen.has(text)) return
    seen.add(text)
    recorded.push(text)
  }
  const wrap = fn => typeof fn !== 'function' ? fn : new Proxy(fn, {
    apply(target, self, args) { args.forEach(record); return Reflect.apply(target, self, args) },
  })

  const swallow = new Proxy(function () {}, {
    get: (_, prop) => (prop === 'then' || typeof prop === 'symbol' ? undefined : swallow),
    apply: () => swallow,
  })
  const scopes = [[]]
  const pending = []
  let failures = 0
  const runGuarded = fn => {
    try {
      for (const scope of scopes) for (const hook of scope) hook()
      const out = fn()
      if (out && typeof out.then === 'function') pending.push(out.catch(() => { failures++ }))
    } catch { failures++ }
  }
  globalThis.__corpusShim = {
    wrap,
    describe: (_, fn) => { scopes.push([]); try { fn() } catch { failures++ } scopes.pop() },
    it: (_, fn) => fn && runGuarded(fn),
    beforeEach: fn => scopes.at(-1).push(fn),
    noop: () => {},
    expect: swallow,
    vi: swallow,
  }

  const hooks = registerHooks({
    resolve(specifier, context, next) {
      if (specifier === 'vitest') return { url: 'corpus-shim:vitest', shortCircuit: true }
      const res = next(specifier, context)
      if (context.parentURL === testUrl && exportsOf.has(res.url)) return { ...res, url: res.url + '?rec' }
      return res
    },
    load(url, context, next) {
      if (url === 'corpus-shim:vitest') {
        const src = 'const S = globalThis.__corpusShim\n' +
          'export const describe = S.describe, it = S.it, test = S.it, expect = S.expect, vi = S.vi, beforeEach = S.beforeEach, afterEach = S.noop, beforeAll = S.noop, afterAll = S.noop\n'
        return { format: 'module', source: src, shortCircuit: true }
      }
      if (url.endsWith('?rec')) {
        const real = url.slice(0, -4)
        const names = exportsOf.get(real)
        const src = `import * as M from ${JSON.stringify(real)}\nconst w = globalThis.__corpusShim.wrap\n` +
          names.map(n => (n === 'default' ? 'export default w(M.default)' : `export const ${n} = w(M.${n})`)).join('\n')
        return { format: 'module', source: src, shortCircuit: true }
      }
      return next(url, context)
    },
  })
  await import(testUrl)
  await Promise.all(pending)
  hooks.deregister()
  if (failures) console.error(`sync-merge capture: ${failures} test bodies threw under the stubs (ignored)`)
  return recorded
}

function genDoc() {
  for (;;) {
    const target = 200 + int(2801)
    const isObj = rng() < 0.7
    const parts = []
    const keys = []
    let size = 2
    while (size < target) {
      const remaining = Math.max(40, target - size)
      const value = genValue(1, Math.min(remaining, 800))
      let part = value
      if (isObj) {
        const key = keys.length && rng() < 0.08 ? pick(keys) : pick(KEYS)
        keys.push(key)
        part = `${ws()}${key}${ws()}:${ws()}${value}${ws()}`
      } else {
        part = `${ws()}${value}${ws()}`
      }
      const partBytes = Buffer.byteLength(part) + 1
      if (size + partBytes > 3000) break
      parts.push(part)
      size += partBytes
    }
    const text = ws() + (isObj ? `{${parts.join(',')}}` : `[${parts.join(',')}]`) + ws()
    const bytes = Buffer.byteLength(text)
    if (bytes >= 200 && bytes <= 3000) return text
  }
}

function ws() {
  if (rng() < 0.6) return ''
  return Array.from({ length: 1 + int(3) }, () => pick([' ', '\t', '\r'])).join('')
}

function genValue(depth, budget) {
  const r = rng()
  if (depth < 6 && budget > 30 && r < 0.3) return genContainer(depth, budget)
  if (r < 0.6) return genNumber()
  if (r < 0.9) return genString()
  return pick(['true', 'false', 'null'])
}

function genContainer(depth, budget) {
  const isObj = rng() < 0.55
  const n = int(8)
  const parts = []
  const keys = []
  let size = 2
  for (let i = 0; i < n && size < budget; i++) {
    const value = genValue(depth + 1, Math.max(10, (budget - size) / 2))
    if (isObj) {
      const key = keys.length && rng() < 0.08 ? pick(keys) : pick(KEYS)
      keys.push(key)
      parts.push(`${ws()}${key}${ws()}:${ws()}${value}${ws()}`)
    } else {
      parts.push(`${ws()}${value}${ws()}`)
    }
    size += Buffer.byteLength(parts.at(-1)) + 1
  }
  if (!parts.length && rng() < 0.5) return isObj ? `{${ws()}}` : `[${ws()}]`
  return isObj ? `{${parts.join(',')}}` : `[${parts.join(',')}]`
}

function genNumber() {
  switch (int(8)) {
    case 0: {
      const view = new DataView(new ArrayBuffer(8))
      view.setUint32(0, int(2 ** 32)); view.setUint32(4, int(2 ** 32))
      const x = view.getFloat64(0)
      if (!Number.isFinite(x)) return '0'
      const s = Object.is(x, -0) ? '-0' : String(x)
      return rng() < 0.3 ? s.replace('e', 'E') : s
    }
    case 1: {
      if (rng() < 0.3) return (rng() < 0.3 ? '-' : '') + (1 + int(9)) + Array.from({ length: int(25) }, () => int(10)).join('')
      return String((rng() < 0.3 ? -1 : 1) * int(2 ** 31))
    }
    case 2: return String(Math.round(rng() * 3000) / pick([10, 100, 4]))
    case 3: return String(1600000000000 + int(300000000000))
    case 4: return pick(['-0', '0', '-0.0', '0e0', '-0E-0', '0.0'])
    case 5: {
      const e = int(36) - 10
      return pick([`1e${e}`, `1E${e}`, e >= 0 ? `1e+${e}` : `1e${e}`, String(10 ** e), `10e${e - 1}`])
    }
    case 6: {
      const mantissa = `${1 + int(9)}.${Array.from({ length: 1 + int(16) }, () => int(10)).join('')}`
      const exp = int(600) - 300
      const sign = exp < 0 ? '-' : pick(['', '+'])
      return `${rng() < 0.3 ? '-' : ''}${mantissa}${pick(['e', 'E'])}${sign}${Math.abs(exp)}`
    }
    default: {
      const x = rng() * 10 ** (int(30) - 10)
      return rng() < 0.5 ? x.toExponential(int(17)) : String(x)
    }
  }
}

function genString() {
  return '"' + Array.from({ length: int(9) }, () => pick(STRING_PIECES)).join('') + '"'
}

function buildLarge() {
  const DAY = 86400000
  const state = structuredClone(demoState)
  const source = demoState.workouts
  const workouts = []
  for (let i = 0; i < 2000; i++) {
    const w = structuredClone(source[i % source.length])
    const shift = (i + 1) * DAY
    w.id = 'lg' + i.toString(36).padStart(4, '0')
    w.start -= shift
    if (w.end) w.end -= shift
    w.d = new Date(w.start).toISOString().slice(0, 10)
    for (const [ei, entry] of w.entries.entries()) {
      for (const set of entry.sets) {
        if (typeof set.w === 'number') set.w = Math.round(set.w * (0.8 + rng() * 0.4) * 10) / 10
        if (rng() < 0.2) set.rir = int(5)
        else if (rng() < 0.2) set.rpe = 6 + int(9) / 2
        if (i % 7 === 0 && ei === 0) set.sides = { L: { w: set.w, r: set.r, done: true }, R: { w: set.w, r: Math.max(0, (set.r || 0) - 1), done: true } }
      }
      if (entry.topW != null) entry.topW = Math.max(0, ...entry.sets.map(s => s.w || 0))
    }
    if (i % 10 === 0) w.note = `โน้ตครั้งที่ ${i}: หนักแต่ไหว`
    workouts.push(w)
  }
  state.workouts = workouts
  const TARGET = 5_000_000
  let size = Buffer.byteLength(JSON.stringify(state))
  const older = []
  let t = FIXED_NOW - 6000 * DAY
  while (size < TARGET) {
    t += DAY / 4
    const entry = { d: new Date(t).toISOString().slice(0, 10), w: Math.round((70 + rng() * 20) * 10) / 10, t }
    size += Buffer.byteLength(JSON.stringify(entry)) + 1
    older.push(entry)
  }
  state.bodyweight = [...older, ...state.bodyweight]
  return JSON.stringify(state)
}
