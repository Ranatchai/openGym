import { afterAll, vi } from 'vitest'
import { mkdirSync, writeFileSync } from 'node:fs'
import { randomUUID } from 'node:crypto'
import { join } from 'node:path'
import { RECORDED_MODULES } from './modules.js'
import { wrapExport } from './recorder.js'

const out = process.env.RECORD_FIXTURES_OUT
if (!out) throw new Error('RECORD_FIXTURES_OUT must name the directory the recorder writes to')

// Tests that build data from today's date (the demo profile) record different calls each day,
// so the clock starts at a fixed instant. It still ticks: tests that wait on Date.now() break
// on a frozen one.
const RealDate = Date
const offset = RealDate.parse('2026-10-05T12:00:00Z') - RealDate.now()
function ShiftedDate(...args) {
  if (!new.target) return new RealDate(RealDate.now() + offset).toString()
  return Reflect.construct(RealDate, args.length ? args : [RealDate.now() + offset], new.target)
}
ShiftedDate.prototype = RealDate.prototype
ShiftedDate.now = () => RealDate.now() + offset
ShiftedDate.parse = RealDate.parse
ShiftedDate.UTC = RealDate.UTC
globalThis.Date = ShiftedDate

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
