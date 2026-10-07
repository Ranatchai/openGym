#!/bin/sh
set -eu
cd "$(dirname "$0")/../.."
fixtures=ios-native/OpenGymCore/Tests/OpenGymCoreTests/Fixtures
resources=ios-native/OpenGymApp/Resources
if [ -z "${CHECK_CORPUS_SKIP_GENERATE:-}" ]; then
  if [ -z "${CHECK_CORPUS_SKIP_RECORDER:-}" ]; then
    node ios-native/tools/gen-json-corpus.mjs
    node ios-native/tools/gen-fixtures.mjs
  fi
  node ios-native/tools/export-exercises.mjs
  node ios-native/tools/convert-locales.mjs
fi
drift=$(git status --porcelain --untracked-files=all -- "$fixtures" "$resources")
if [ -n "$drift" ]; then
  git diff --stat -- "$fixtures" "$resources"
  cat <<EOF
check-corpus: the generated files differ from the committed ones:
$drift

A frontend test, a recorded JS module, the exercise catalogue or a locale
pack changed what these files hold. Regenerate them, check the Swift side
against them, and commit them:
  node ios-native/tools/gen-json-corpus.mjs
  node ios-native/tools/gen-fixtures.mjs
  node ios-native/tools/export-exercises.mjs
  node ios-native/tools/convert-locales.mjs
  (cd ios-native/OpenGymCore && swift test)
  git add $fixtures $resources && git commit
If swift test fails, the JS change needs the same change in the Swift port.
A generated file git does not track (??) must be committed or deleted.
EOF
  exit 1
fi
