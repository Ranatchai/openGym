class Unrepresentable extends Error {}

export function encode(value, seen = new Set()) {
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
      if (key === '$js' || key === '__proto__') throw new Unrepresentable(`an object with its own "${key}" key`)
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
    return { unrepresentable: error instanceof Unrepresentable ? error.message : `a value that threw while encoding: ${messageOf(error)}` }
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

export function wrapExport(name, fn, records) {
  const wrapper = function (...args) {
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
  return Object.defineProperties(wrapper, { name: { value: fn.name }, length: { value: fn.length } })
}
