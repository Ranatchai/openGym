import fs from 'node:fs'

const [file, runsArg] = process.argv.slice(2)
if (!file) {
  console.error('usage: node ios-native/tools/bench-json.mjs <file> [runs=5]')
  process.exit(2)
}
const runs = Number(runsArg ?? 5)
const buf = fs.readFileSync(file)

const once = () => {
  const t0 = performance.now()
  const s = buf.toString('utf8')
  const v = JSON.parse(s)
  const t1 = performance.now()
  const out = JSON.stringify(v)
  const t2 = performance.now()
  return { parseMs: t1 - t0, stringifyMs: t2 - t1, totalMs: t2 - t0, matches: Buffer.compare(Buffer.from(out, 'utf8'), buf) === 0 }
}

once()
once()
const results = []
for (let run = 1; run <= runs; run++) {
  const r = once()
  results.push(r)
  console.log(JSON.stringify({ run, parseMs: r.parseMs, stringifyMs: r.stringifyMs, totalMs: r.totalMs }))
}
const median = xs => {
  const s = [...xs].sort((a, b) => a - b)
  const m = s.length >> 1
  return s.length % 2 ? s[m] : (s[m - 1] + s[m]) / 2
}
console.log(JSON.stringify({
  node: process.version,
  bytes: buf.length,
  runs,
  medianTotalMs: median(results.map(r => r.totalMs)),
  medianParseMs: median(results.map(r => r.parseMs)),
  medianStringifyMs: median(results.map(r => r.stringifyMs)),
  outputMatches: results.every(r => r.matches),
}))
