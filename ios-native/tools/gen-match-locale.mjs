#!/usr/bin/env node
// Records the web's matchLocale answers for the app's language-resolver test.
// Usage: node ios-native/tools/gen-match-locale.mjs [--check]
import { readFileSync, writeFileSync } from 'node:fs'
import { fileURLToPath } from 'node:url'
import { matchLocale } from '../../frontend/src/lib/default-lang.js'

const out = fileURLToPath(new URL('../OpenGymApp/OpenGymAppTests/match-locale.json', import.meta.url))

const tags = [
  'en', 'en-US', 'en-GB', 'EN_us', ' en ', '', '   ',
  'de', 'de-AT', 'de-CH', 'de_ch', 'DE-CH',
  'pt', 'pt-PT', 'pt-BR', 'pt_BR', 'pt-br', 'PT-BR',
  'zh', 'zh-Hans', 'zh-Hans-CN', 'zh-Hant', 'zh-Hant-TW', 'zh-TW', 'zh-HK', 'zh_Hant_HK',
  'yue-Hant-HK', 'th', 'th-TH', 'ar', 'ar-SA', 'ar-EG',
  'ko-KR', 'hi-IN', 'uk-UA', 'ru-RU', 'tr-TR', 'pl-PL', 'hu-HU', 'it-IT', 'es-419', 'es-MX', 'fr-CA',
  'ja', 'ja-JP', 'nl-NL', 'sr-Latn-RS', '-de', 'de-', 'x-klingon',
]

const json = JSON.stringify(tags.map(tag => ({ tag, match: matchLocale(tag) })), null, 2) + '\n'

if (process.argv.includes('--check')) {
  if (readFileSync(out, 'utf8') !== json) {
    console.error('match-locale.json is stale; run node ios-native/tools/gen-match-locale.mjs')
    process.exit(1)
  }
} else {
  writeFileSync(out, json)
}
console.log(`${tags.length} tags`)
