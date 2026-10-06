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

const tmp = fs.mkdtempSync(path.join(os.tmpdir(), 'opengym-fixtures-'))
const raw = path.join(tmp, 'records')
const report = path.join(tmp, 'run.json')
fs.mkdirSync(raw)
const vitest = spawnSync(path.join(FRONTEND, 'node_modules/.bin/vitest'), ['run', '--reporter=default', `--reporter=${path.join(import.meta.dirname, 'gen-fixtures-reporter.mjs')}`, ...process.argv.slice(2)], {
  cwd: FRONTEND,
  stdio: ['ignore', 'inherit', 'inherit'],
  env: { ...process.env, RECORD_FIXTURES: '1', RECORD_FIXTURES_OUT: raw, GEN_FIXTURES_REPORT: report, TZ: 'UTC' },
})
if (vitest.error) throw vitest.error

const recordings = fs.readdirSync(raw).map(file => JSON.parse(fs.readFileSync(path.join(raw, file), 'utf8')))
const recordingFiles = new Set(recordings.map(recording => recording.testFile))
const run = fs.existsSync(report) ? JSON.parse(fs.readFileSync(report, 'utf8')) : { failures: [], unhandled: [] }
const recordedSources = new Set(RECORDED_MODULES.map(module => path.join(FRONTEND, `src/lib/${module}.js`)))
const blocking = run.failures.filter(failure => recordingFiles.has(failure.file) || reachesRecordedModule(failure.file))
const unrelated = run.failures.filter(failure => !blocking.includes(failure))
if (unrelated.length) {
  console.warn(`gen-fixtures: ignoring ${unrelated.length} failing test(s) in files that import no module of ${RECORDED_MODULES.join(', ')}:\n  ${unrelated.map(describe).join('\n  ')}`)
}
if (blocking.length) {
  console.error(`gen-fixtures: ${blocking.length} failing test(s) in files that record calls to or import ${RECORDED_MODULES.join(', ')}; a failing file can stop before calls it would record, so no fixture was written:\n  ${blocking.map(describe).join('\n  ')}`)
  console.error('Reproduce one under the recorder with: cd frontend && RECORD_FIXTURES=1 RECORD_FIXTURES_OUT=$(mktemp -d) TZ=UTC npx vitest run <test file>')
  process.exit(1)
}
if (run.unhandled.length) {
  console.error(`gen-fixtures: vitest caught ${run.unhandled.length} unhandled error(s), which can stop a test file before calls it would record, so no fixture was written:\n  ${run.unhandled.join('\n  ')}`)
  process.exit(1)
}
if (vitest.status !== 0 && !unrelated.length) {
  console.error(`gen-fixtures: vitest exited ${vitest.status} without naming a failing test; see its output above`)
  process.exit(1)
}

const problems = []
fs.mkdirSync(OUT, { recursive: true })
for (const module of RECORDED_MODULES) {
  const calls = new Map()
  let files = 0
  for (const recording of recordings) {
    const records = recording.records[module] ?? []
    if (records.length) files++
    for (const record of records) {
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
  console.log(`gen-fixtures: ${module} ${sorted.length} calls from ${files} test files`)
}
fs.rmSync(tmp, { recursive: true, force: true })

if (problems.length) {
  console.error(`gen-fixtures: ${problems.length} call(s) cannot be recorded:\n  ${[...new Set(problems)].join('\n  ')}`)
  process.exit(1)
}

function reachesRecordedModule(testFile) {
  const seen = new Set([testFile])
  for (const file of seen) {
    if (recordedSources.has(file)) return true
    const source = fs.readFileSync(file, 'utf8')
    for (const [, specifier] of source.matchAll(/(?:\bfrom|\bimport)\s*\(?\s*['"`](\.{1,2}\/[^'"`]+)['"`]/g)) {
      const imported = resolveImport(path.dirname(file), specifier)
      if (imported) seen.add(imported)
    }
  }
  return false
}

function resolveImport(dir, specifier) {
  const base = path.resolve(dir, specifier)
  return [base, ...['.js', '.jsx', '.mjs', '/index.js', '/index.jsx'].map(ext => base + ext)].find(candidate => fs.existsSync(candidate) && fs.statSync(candidate).isFile())
}

function describe({ file, test }) {
  return `${path.relative(REPO, file)} > ${test}`
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
