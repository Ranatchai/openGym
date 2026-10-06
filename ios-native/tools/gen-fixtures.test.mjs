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
