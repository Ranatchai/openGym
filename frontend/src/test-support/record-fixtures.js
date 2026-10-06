import { afterAll, vi } from 'vitest'
import { mkdirSync, writeFileSync } from 'node:fs'
import { randomUUID } from 'node:crypto'
import { join } from 'node:path'
import { RECORDED_MODULES } from './modules.js'

const out = process.env.RECORD_FIXTURES_OUT
if (!out) throw new Error('RECORD_FIXTURES_OUT must name the directory the recorder writes to')

vi.setSystemTime(new Date('2026-07-27T12:00:00Z'))
Math.random = mulberry32(0x6f70656e)

function mulberry32(seed) {
  let a = seed >>> 0
  return () => {
    a = (a + 0x6d2b79f5) >>> 0
    let t = Math.imul(a ^ (a >>> 15), 1 | a)
    t = (t + Math.imul(t ^ (t >>> 7), 61 | t)) ^ t
    return ((t ^ (t >>> 14)) >>> 0) / 4294967296
  }
}

class Unrepresentable extends Error {}

function encode(value, seen = new Set()) {
  if (value === undefined) return { $js: 'undefined' }
  if (value === null || typeof value === 'boolean' || typeof value === 'string') return value
  if (typeof value === 'number') {
    if (Number.isNaN(value)) return { $js: 'NaN' }
    if (value === Infinity) return { $js: 'Infinity' }
    if (value === -Infinity) return { $js: '-Infinity' }
    if (Object.is(value, -0)) return { $js: '-0' }
    return value
  }
  if (typeof value !== 'object') throw new Unrepresentable(typeof value)
  if (seen.has(value)) throw new Unrepresentable('a cyclic reference')
  seen.add(value)
  try {
    if (Array.isArray(value)) {
      const items = []
      for (let i = 0; i < value.length; i++) {
        if (!(i in value)) throw new Unrepresentable('an array hole')
        items.push(encode(value[i], seen))
      }
      return items
    }
    const proto = Object.getPrototypeOf(value)
    if (proto !== Object.prototype && proto !== null) throw new Unrepresentable(Object.prototype.toString.call(value))
    if (Object.getOwnPropertySymbols(value).length) throw new Unrepresentable('a symbol key')
    const object = {}
    for (const key of Object.keys(value)) {
      if (key === '$js') throw new Unrepresentable('an object with its own "$js" key')
      object[key] = encode(value[key], seen)
    }
    return object
  } finally {
    seen.delete(value)
  }
}

function encodeOrUnrepresentable(encodeIt) {
  try {
    return { value: encodeIt() }
  } catch (error) {
    if (error instanceof Unrepresentable) return { unrepresentable: error.message }
    throw error
  }
}

const messageOf = error => String(error?.message ?? error)

function recordingCallback(fn) {
  const calls = []
  const wrapped = function (...args) {
    const encodedArgs = encodeOrUnrepresentable(() => encode(args))
    if (encodedArgs.unrepresentable) {
      calls.push({ unrepresentable: `a callback argument holds ${encodedArgs.unrepresentable}` })
      return fn.apply(this, args)
    }
    let result
    try {
      result = fn.apply(this, args)
    } catch (error) {
      calls.push({ args: encodedArgs.value, throws: messageOf(error) })
      throw error
    }
    const encodedResult = encodeOrUnrepresentable(() => encode(result))
    calls.push(encodedResult.unrepresentable
      ? { unrepresentable: `a callback result holds ${encodedResult.unrepresentable}` }
      : { args: encodedArgs.value, result: encodedResult.value })
    return result
  }
  return { wrapped, tag: { $js: 'function', calls } }
}

function wrapExport(name, fn, records) {
  return function (...args) {
    const snapshot = () => JSON.stringify(args.map(arg => (typeof arg === 'function' ? null : encode(arg))))
    const before = encodeOrUnrepresentable(snapshot)
    if (before.unrepresentable) {
      records.push({ fn: name, unrepresentable: `an argument holds ${before.unrepresentable}` })
      return fn.apply(this, args)
    }
    const callbacks = args.map(arg => (typeof arg === 'function' ? recordingCallback(arg) : null))
    const encodedArgs = JSON.parse(before.value).map((arg, i) => callbacks[i]?.tag ?? arg)
    let result
    try {
      result = fn.apply(this, args.map((arg, i) => callbacks[i]?.wrapped ?? arg))
    } catch (error) {
      records.push({ fn: name, args: encodedArgs, throws: messageOf(error) })
      throw error
    }
    const after = encodeOrUnrepresentable(snapshot)
    const encodedResult = encodeOrUnrepresentable(() => encode(result))
    if (after.value !== before.value) records.push({ fn: name, unrepresentable: 'the call mutated its arguments' })
    else if (encodedResult.unrepresentable) records.push({ fn: name, unrepresentable: `the result holds ${encodedResult.unrepresentable}` })
    else records.push({ fn: name, args: encodedArgs, result: encodedResult.value })
    return result
  }
}

const recorded = {}
for (const name of RECORDED_MODULES) {
  const records = (recorded[name] = [])
  vi.doMock(`../lib/${name}.js`, async importOriginal => {
    const original = await importOriginal()
    const wrapped = {}
    for (const [key, value] of Object.entries(original)) {
      wrapped[key] = typeof value === 'function' ? wrapExport(key, value, records) : value
    }
    return wrapped
  })
}

afterAll(() => {
  const file = `${randomUUID()}.json`
  for (const [name, records] of Object.entries(recorded)) {
    if (!records.length) continue
    const dir = join(out, name)
    mkdirSync(dir, { recursive: true })
    writeFileSync(join(dir, file), JSON.stringify(records))
  }
})
