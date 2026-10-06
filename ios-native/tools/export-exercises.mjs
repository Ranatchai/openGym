// Writes the runtime exercise catalogue (EXDB with the muscle overlays applied) for the iOS app.
// Usage: node ios-native/tools/export-exercises.mjs
import { writeFileSync } from 'node:fs'
import { join } from 'node:path'
import { CATALOGUE } from '../../frontend/src/lib/exercises.js'

const out = join(import.meta.dirname, '../OpenGymApp/Resources/exercises.json')
writeFileSync(out, JSON.stringify(CATALOGUE))
console.log(`exercises.json: ${CATALOGUE.length} exercises`)
