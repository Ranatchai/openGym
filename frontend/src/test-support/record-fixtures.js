import { afterAll, vi } from 'vitest'
import { mkdirSync, writeFileSync } from 'node:fs'
import { randomUUID } from 'node:crypto'
import { join } from 'node:path'
import { RECORDED_MODULES } from './modules.js'
import { wrapExport } from './recorder.js'

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
