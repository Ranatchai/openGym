import { test } from 'node:test'
import assert from 'node:assert/strict'
import { wrapExport } from '../../frontend/src/test-support/recorder.js'

const record = (fn, ...args) => {
  const records = []
  const result = wrapExport(fn.name, fn, records)(...args)
  return { result, records }
}

test('an own "__proto__" key in an argument is flagged, not dropped', () => {
  const { records } = record(function keys(o) { return Object.keys(o).length }, JSON.parse('{"__proto__":{"rir":1},"w":2}'))
  assert.deepEqual(records, [{ fn: 'keys', unrepresentable: 'an argument holds an object with its own "__proto__" key' }])
})

test('an own "__proto__" key in a result is flagged, not dropped', () => {
  const { records } = record(function parse() { return JSON.parse('{"__proto__":{"rir":1}}') })
  assert.deepEqual(records, [{ fn: 'parse', unrepresentable: 'the result holds an object with its own "__proto__" key' }])
})

test('the wrapper keeps the export\'s name and length', () => {
  function normalizeRepRange(reps, repsMin, stride) { return [reps, repsMin, stride] }
  const wrapped = wrapExport('normalizeRepRange', normalizeRepRange, [])
  assert.equal(wrapped.name, 'normalizeRepRange')
  assert.equal(wrapped.length, 3)
})

test('an argument whose getter throws reaches the export unchanged and is flagged', () => {
  const arg = { get w() { throw new Error('getter') } }
  const { result, records } = record(function isWarmupRow(set) { return typeof set }, arg)
  assert.equal(result, 'object')
  assert.deepEqual(records, [{ fn: 'isWarmupRow', unrepresentable: 'an argument holds a value that threw while encoding: getter' }])
})

test('an argument nested too deep to encode reaches the export unchanged and is flagged', () => {
  let deep = {}
  for (let i = 0; i < 20000; i++) deep = { next: deep }
  const { result, records } = record(function isSideSet(set) { return !!set.sides }, deep)
  assert.equal(result, false)
  assert.equal(records.length, 1)
  assert.match(records[0].unrepresentable, /^an argument holds a value that threw while encoding: /)
})

test('a result whose getter throws is returned unchanged and is flagged', () => {
  const out = { get w() { throw new Error('getter') } }
  const { result, records } = record(function make() { return out })
  assert.equal(result, out)
  assert.deepEqual(records, [{ fn: 'make', unrepresentable: 'the result holds a value that threw while encoding: getter' }])
})
