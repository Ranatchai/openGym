import { afterAll, expect, vi } from 'vitest'
import { writeFileSync } from 'node:fs'
import { randomUUID } from 'node:crypto'
import { join } from 'node:path'
import { RECORDED_MODULES } from './modules.js'
import { wrapExport } from './recorder.js'

const out = process.env.RECORD_FIXTURES_OUT
if (!out) throw new Error('RECORD_FIXTURES_OUT must name the directory the recorder writes to')

const RealDate = Date
const RECORDING_START = '2026-10-05T12:00:00Z'
const offset = RealDate.parse(RECORDING_START) - RealDate.now()
function DateTickingFromRecordingStart(...args) {
  if (!new.target) return new RealDate(RealDate.now() + offset).toString()
  return Reflect.construct(RealDate, args.length ? args : [RealDate.now() + offset], new.target)
}
DateTickingFromRecordingStart.prototype = RealDate.prototype
DateTickingFromRecordingStart.now = () => RealDate.now() + offset
DateTickingFromRecordingStart.parse = RealDate.parse
DateTickingFromRecordingStart.UTC = RealDate.UTC
globalThis.Date = DateTickingFromRecordingStart

const testFile = expect.getState().testPath
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
  if (Object.values(recorded).some(records => records.length)) {
    writeFileSync(join(out, `${randomUUID()}.json`), JSON.stringify({ testFile, records: recorded }))
  }
})
