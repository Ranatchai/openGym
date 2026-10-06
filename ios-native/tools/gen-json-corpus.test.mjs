import { test } from 'node:test'
import assert from 'node:assert/strict'
import fs from 'node:fs'
import os from 'node:os'
import path from 'node:path'
import { execFileSync } from 'node:child_process'

const REPO = path.resolve(import.meta.dirname, '../..')
const GENERATOR = path.join(REPO, 'ios-native/tools/gen-json-corpus.mjs')
const SYNC_MERGE_TEST = path.join(REPO, 'frontend/src/lib/sync-merge.test.js')

const generate = (out, testFile) => execFileSync('node', [GENERATOR, '--out', out, '--sync-merge-test', testFile], { stdio: 'pipe' })
const caseNames = out => fs.readdirSync(path.join(out, 'cases')).sort()
const caseBytes = (out, name, file) => fs.readFileSync(path.join(out, 'cases', name, file))

test('a sync-merge test inserted first adds its own cases and moves no other', () => {
  const tmp = fs.mkdtempSync(path.join(os.tmpdir(), 'json-corpus-'))
  const scratch = path.join(path.dirname(SYNC_MERGE_TEST), 'sync-merge.corpus-scratch.js')
  try {
    const before = path.join(tmp, 'before')
    const after = path.join(tmp, 'after')
    generate(before, SYNC_MERGE_TEST)

    const source = fs.readFileSync(SYNC_MERGE_TEST, 'utf8')
    const firstDescribe = source.indexOf('\ndescribe(')
    assert.ok(firstDescribe > 0)
    const inserted = [
      '',
      "describe('inserted first', () => {",
      "  it('merges two states no other test merges', () => {",
      "    mergeStates(base({ _ts: 1, workouts: [workout('inserted-w1')] }), base({ _ts: 2, workouts: [workout('inserted-w2')] }))",
      '  })',
      '})',
      '',
    ].join('\n')
    fs.writeFileSync(scratch, source.slice(0, firstDescribe) + inserted + source.slice(firstDescribe))
    generate(after, scratch)

    const namesBefore = caseNames(before)
    const namesAfter = caseNames(after)
    const kept = namesBefore.filter(name => namesAfter.includes(name))
    assert.deepEqual(kept, namesBefore, 'every case keeps its name')
    for (const name of kept) {
      for (const file of ['input.json', 'expected.json']) {
        assert.ok(caseBytes(before, name, file).equals(caseBytes(after, name, file)), `${name}/${file} keeps its bytes`)
      }
    }
    const added = namesAfter.filter(name => !namesBefore.includes(name))
    assert.equal(added.length, 2, `added: ${added.join(', ')}`)
    for (const name of added) assert.match(caseBytes(after, name, 'input.json').toString(), /inserted-w[12]/)
  } finally {
    fs.rmSync(scratch, { force: true })
    fs.rmSync(tmp, { recursive: true, force: true })
  }
})
