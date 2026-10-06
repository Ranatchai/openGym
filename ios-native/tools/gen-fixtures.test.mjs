import { test } from 'node:test'
import assert from 'node:assert/strict'
import fs from 'node:fs'
import path from 'node:path'
import { spawnSync } from 'node:child_process'

const REPO = path.resolve(import.meta.dirname, '../..')
const GENERATOR = path.join(REPO, 'ios-native/tools/gen-fixtures.mjs')
const FIXTURES = path.join(REPO, 'ios-native/OpenGymCore/Tests/OpenGymCoreTests/Fixtures/conformance')
const LIB = path.join(REPO, 'frontend/src/lib')

const fixtureBytes = () => Object.fromEntries(fs.readdirSync(FIXTURES).map(file => [file, fs.readFileSync(path.join(FIXTURES, file), 'utf8')]))

test('a test that fails only under the recorder fails the generator by name and writes no fixture', () => {
  const recording = path.join(LIB, 'rep-range.recorder-scratch.test.js')
  const unrelated = path.join(LIB, 'unrelated.recorder-scratch.test.js')
  const before = fixtureBytes()
  try {
    fs.writeFileSync(recording, [
      "import { it, expect } from 'vitest'",
      "import { normalizeRepRange } from './rep-range.js'",
      "it('passes only without the recorder', () => {",
      '  normalizeRepRange(8, 6)',
      '  expect(process.env.RECORD_FIXTURES).toBeUndefined()',
      '})',
      '',
    ].join('\n'))
    fs.writeFileSync(unrelated, [
      "import { it, expect } from 'vitest'",
      "it('fails without calling a recorded module', () => { expect(1).toBe(2) })",
      '',
    ].join('\n'))
    const run = spawnSync('node', [GENERATOR, 'recorder-scratch'], { encoding: 'utf8' })
    assert.equal(run.status, 1)
    assert.match(run.stderr, /1 failing test\(s\) in files that record calls/)
    assert.match(run.stderr, /frontend\/src\/lib\/rep-range\.recorder-scratch\.test\.js > passes only without the recorder/)
    assert.match(run.stderr, /ignoring 1 failing test\(s\)[^\n]*\n {2}frontend\/src\/lib\/unrelated\.recorder-scratch\.test\.js > fails without calling a recorded module/)
    assert.deepEqual(fixtureBytes(), before)
  } finally {
    fs.rmSync(recording, { force: true })
    fs.rmSync(unrelated, { force: true })
  }
})

function runWithScratch(files) {
  const before = fixtureBytes()
  try {
    for (const [name, lines] of Object.entries(files)) fs.writeFileSync(path.join(LIB, name), [...lines, ''].join('\n'))
    const run = spawnSync('node', [GENERATOR, 'failopen-scratch'], { encoding: 'utf8' })
    const after = fixtureBytes()
    return { run, rewritten: Object.keys(before).filter(file => after[file] !== before[file]) }
  } finally {
    for (const name of Object.keys(files)) fs.rmSync(path.join(LIB, name), { force: true })
    for (const [file, text] of Object.entries(before)) fs.writeFileSync(path.join(FIXTURES, file), text)
  }
}

test('a file that fails under the recorder before its first recorded call fails the generator by name', () => {
  const { run, rewritten } = runWithScratch({
    'rep-range.failopen-scratch.test.js': [
      "import { it, expect } from 'vitest'",
      "import { normalizeRepRange } from './rep-range.js'",
      "it('fails under the recorder before its first recorded call', () => {",
      '  expect(process.env.RECORD_FIXTURES).toBeUndefined()',
      '  expect(normalizeRepRange(12345, 6)).toBeDefined()',
      '})',
    ],
  })
  assert.equal(run.status, 1)
  assert.match(run.stderr, /1 failing test\(s\) in files that record calls[^\n]*\n {2}frontend\/src\/lib\/rep-range\.failopen-scratch\.test\.js > fails under the recorder before its first recorded call/)
  assert.deepEqual(rewritten, [])
})

test('a file that reaches a recorded module through another module and fails at import fails the generator by name', () => {
  const { run, rewritten } = runWithScratch({
    'via.failopen-scratch.js': ["export { normalizeRepRange } from './rep-range.js'"],
    'import.failopen-scratch.test.js': [
      "import { it } from 'vitest'",
      "import { normalizeRepRange } from './via.failopen-scratch.js'",
      "if (process.env.RECORD_FIXTURES) throw new Error('import fails under the recorder')",
      "it('records a call', () => { normalizeRepRange(12345, 6) })",
    ],
  })
  assert.equal(run.status, 1)
  assert.match(run.stderr, /1 failing test\(s\) in files that record calls[^\n]*\n {2}frontend\/src\/lib\/import\.failopen-scratch\.test\.js > /)
  assert.deepEqual(rewritten, [])
})

test('an unhandled error fails the generator even when an unrelated test also fails', () => {
  const { run, rewritten } = runWithScratch({
    'rep-range.failopen-scratch.test.js': [
      "import { it } from 'vitest'",
      "import { normalizeRepRange } from './rep-range.js'",
      "it('records a call, then throws outside the test', () => {",
      '  normalizeRepRange(8, 6)',
      "  setTimeout(() => { throw new Error('thrown outside any test') }, 0)",
      '})',
    ],
    'unrelated.failopen-scratch.test.js': [
      "import { it, expect } from 'vitest'",
      "it('fails without calling a recorded module', () => { expect(1).toBe(2) })",
    ],
  })
  assert.equal(run.status, 1)
  assert.match(run.stderr, /gen-fixtures: [^\n]*unhandled[^\n]*\n[^\n]*thrown outside any test/)
  assert.deepEqual(rewritten, [])
})

test('a failing file that reaches no recorded module is listed and ignored', () => {
  const { run, rewritten } = runWithScratch({
    'rep-range.failopen-scratch.test.js': [
      "import { it } from 'vitest'",
      "import { normalizeRepRange } from './rep-range.js'",
      "it('records a call', () => { normalizeRepRange(8, 6) })",
    ],
    'unrelated.failopen-scratch.test.js': [
      "import { it, expect } from 'vitest'",
      "it('fails without calling a recorded module', () => { expect(1).toBe(2) })",
    ],
  })
  assert.match(run.stderr, /ignoring 1 failing test\(s\)[^\n]*\n {2}frontend\/src\/lib\/unrelated\.failopen-scratch\.test\.js > fails without calling a recorded module/)
  assert.match(run.stdout, /gen-fixtures: rep-range 1 calls from 1 test files/)
  assert.deepEqual(rewritten, ['rep-range.json', 'workout-model.json'])
})
