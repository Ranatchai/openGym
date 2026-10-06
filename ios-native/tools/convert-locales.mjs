// Converts the web app's locale packs into one String Catalog for the iOS app.
// Usage: node ios-native/tools/convert-locales.mjs
//
// Keys stay the English source strings. Every value, including the English one, is a format
// string: a literal % becomes %%, and {n} becomes %(n+1)$@, so the app always runs
// String(format:) and gets what t(key, ...args) gives on the web.
import { writeFileSync } from 'node:fs'
import { join } from 'node:path'
import { LANGS, baseLang, derivePack } from '../../frontend/src/lib/i18n-core.js'

const SOURCE = 'en'
const localesDir = join(import.meta.dirname, '../../frontend/src/locales')
const out = join(import.meta.dirname, '../OpenGymApp/Resources/Localizable.xcstrings')

const toFormat = s => s.replaceAll('%', '%%').replace(/\{(\d+)\}/g, (_, n) => `%${Number(n) + 1}$@`)
const sortKeys = obj => Object.fromEntries(Object.keys(obj).sort().map(k => [k, obj[k]]))
const unit = value => ({ stringUnit: { state: 'translated', value } })

const langs = Object.keys(LANGS).filter(l => l !== SOURCE).sort()
const packs = {}
for (const lang of langs) {
  const { default: pack } = await import(join(localesDir, `${baseLang(lang)}.js`))
  packs[lang] = derivePack(lang, pack)
}

const keys = [...new Set(langs.flatMap(l => Object.keys(packs[l])))].sort()
const strings = {}
for (const key of keys) {
  const localizations = {}
  const source = toFormat(key)
  if (source !== key) localizations[SOURCE] = unit(source)
  for (const lang of langs) {
    const value = packs[lang][key]
    if (typeof value !== 'string') throw new Error(`${lang} has no translation for ${JSON.stringify(key)}`)
    localizations[lang] = unit(toFormat(value))
  }
  strings[key] = { extractionState: 'manual', localizations: sortKeys(localizations) }
}

writeFileSync(out, JSON.stringify({ sourceLanguage: SOURCE, strings, version: '1.0' }, null, 2) + '\n')
console.log(`Localizable.xcstrings: ${keys.length} keys, ${langs.length} languages + ${SOURCE}`)
