import { writeFileSync } from 'node:fs'
import { join } from 'node:path'
import { LANGS, baseLang, derivePack } from '../../frontend/src/lib/i18n-core.js'

const SOURCE = 'en'
const localesDir = join(import.meta.dirname, '../../frontend/src/locales')
const out = join(import.meta.dirname, '../OpenGymApp/Resources/Localizable.xcstrings')

const toFormatString = s => s.replaceAll('%', '%%').replace(/\{(\d+)\}/g, (_, n) => `%${Number(n) + 1}$@`)
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
  const source = toFormatString(key)
  if (source !== key) localizations[SOURCE] = unit(source)
  for (const lang of langs) {
    const translation = packs[lang][key]
    if (translation) localizations[lang] = unit(toFormatString(translation))
  }
  strings[key] = { extractionState: 'manual', localizations: sortKeys(localizations) }
}

writeFileSync(out, JSON.stringify({ sourceLanguage: SOURCE, strings, version: '1.0' }, null, 2) + '\n')
console.log(`Localizable.xcstrings: ${keys.length} keys, ${langs.length} languages + ${SOURCE}`)
