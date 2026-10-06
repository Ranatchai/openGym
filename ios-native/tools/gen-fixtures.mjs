// Fixture format, opengym-conformance/1:
//   {"format":"opengym-conformance/1","module":"rep-range","exports":["normalizeRepRange"],"calls":[
//   {"fn":"normalizeRepRange","args":[12,8],"result":{"reps":12,"repsMin":8}},
//   {"fn":"...","args":[...],"throws":"<error message>"}
//   ]}
// `exports` lists every exported function, recorded or not. `calls` is deduplicated and sorted by
// fn, then by the JSON text of the call, so a rerun on the same JS writes the same bytes.
//
// Values JSON cannot hold are objects whose only key is "$js":
//   {"$js":"undefined"}  {"$js":"NaN"}  {"$js":"Infinity"}  {"$js":"-Infinity"}  {"$js":"-0"}
//   {"$js":"function","calls":[{"args":[...],"result":...}]}  a function argument, as the calls
//     it answered during the recorded call, which the Swift side replays.
// Anything else (Map, Date, class instances, cycles, array holes, symbols, bigint, a function
// nested inside an argument, an object with its own "$js" key, or a call that mutates its
// arguments) is recorded as unrepresentable and this script exits non-zero naming it.
import { spawnSync } from 'node:child_process'
import fs from 'node:fs'
import os from 'node:os'
import path from 'node:path'
import { pathToFileURL } from 'node:url'

const REPO = path.resolve(import.meta.dirname, '../..')
const FRONTEND = path.join(REPO, 'frontend')
const OUT = path.join(REPO, 'ios-native/OpenGymCore/Tests/OpenGymCoreTests/Fixtures/conformance')
const FORMAT = 'opengym-conformance/1'

const { RECORDED_MODULES } = await import(pathToFileURL(path.join(FRONTEND, 'src/test-support/modules.js')))

const raw = fs.mkdtempSync(path.join(os.tmpdir(), 'opengym-fixtures-'))
const vitest = spawnSync(path.join(FRONTEND, 'node_modules/.bin/vitest'), ['run', ...process.argv.slice(2)], {
  cwd: FRONTEND,
  stdio: ['ignore', 'inherit', 'inherit'],
  env: { ...process.env, RECORD_FIXTURES: '1', RECORD_FIXTURES_OUT: raw, TZ: 'UTC' },
})
if (vitest.error) throw vitest.error
if (vitest.status !== 0) {
  console.warn(`gen-fixtures: vitest exited ${vitest.status}; writing fixtures anyway, a failing test's calls still record what the JS returned and a test that stopped early shows as a fixture diff`)
}

const problems = []
fs.mkdirSync(OUT, { recursive: true })
for (const module of RECORDED_MODULES) {
  const dir = path.join(raw, module)
  const files = fs.existsSync(dir) ? fs.readdirSync(dir) : []
  const calls = new Map()
  for (const file of files) {
    for (const record of JSON.parse(fs.readFileSync(path.join(dir, file), 'utf8'))) {
      const bad = record.unrepresentable ?? unrepresentableCallback(record.args)
      if (bad) problems.push(`${module}.${record.fn}: ${bad}`)
      else calls.set(JSON.stringify(record), record)
    }
  }
  const sorted = [...calls].sort(([a, ra], [b, rb]) => compare(ra.fn, rb.fn) || compare(a, b)).map(([text]) => text)
  const recordedFns = new Set([...calls.values()].map(record => record.fn))
  const source = await import(pathToFileURL(path.join(FRONTEND, `src/lib/${module}.js`)))
  const exports = Object.keys(source).filter(key => typeof source[key] === 'function').sort(compare)
  const unrecorded = exports.filter(fn => !recordedFns.has(fn))
  if (unrecorded.length) problems.push(`${module}: no recorded call for ${unrecorded.join(', ')}`)
  const head = JSON.stringify({ format: FORMAT, module, exports }).slice(0, -1)
  fs.writeFileSync(path.join(OUT, `${module}.json`), `${head},"calls":[\n${sorted.join(',\n')}\n]}\n`)
  console.log(`gen-fixtures: ${module} ${sorted.length} calls from ${files.length} test files`)
}
fs.rmSync(raw, { recursive: true, force: true })

if (problems.length) {
  console.error(`gen-fixtures: ${problems.length} call(s) cannot be recorded:\n  ${[...new Set(problems)].join('\n  ')}`)
  process.exit(1)
}

function unrepresentableCallback(args) {
  for (const arg of args ?? []) {
    if (arg?.$js !== 'function') continue
    const bad = arg.calls.find(call => call.unrepresentable)
    if (bad) return bad.unrepresentable
  }
  return null
}

function compare(a, b) {
  return a < b ? -1 : a > b ? 1 : 0
}
