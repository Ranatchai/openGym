import { writeFileSync } from 'node:fs'
import { join } from 'node:path'
import { CATALOGUE } from '../../frontend/src/lib/exercises.js'

const out = join(import.meta.dirname, '../OpenGymApp/Resources/exercises.json')
writeFileSync(out, JSON.stringify(CATALOGUE))
console.log(`exercises.json: ${CATALOGUE.length} exercises`)
