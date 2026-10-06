import fs from 'node:fs'

export default class GenFixturesReporter {
  onTestRunEnd(testModules, unhandledErrors, reason) {
    const failures = testModules.filter(module => module.state() === 'failed').flatMap(module => {
      const tests = [...module.children.allTests('failed')].map(test => ({ file: module.moduleId, test: test.fullName }))
      return tests.length ? tests : [{ file: module.moduleId, test: `the file failed to run: ${String(module.errors()[0]?.message ?? 'a hook or suite failed').split('\n')[0]}` }]
    })
    const unhandled = unhandledErrors.map(error => `${error.name ?? 'Error'}: ${String(error.message).split('\n')[0]}`)
    fs.writeFileSync(process.env.GEN_FIXTURES_REPORT, JSON.stringify({ reason, failures, unhandled }))
  }
}
