#!/bin/sh
set -eu
cd "$(dirname "$0")/../.."
fixtures=ios-native/OpenGymCore/Tests/OpenGymCoreTests/Fixtures
if [ -z "${CHECK_CORPUS_SKIP_GENERATE:-}" ]; then
  node ios-native/tools/gen-json-corpus.mjs
  node ios-native/tools/gen-fixtures.mjs
fi
drift=$(git status --porcelain --untracked-files=all -- "$fixtures")
if [ -n "$drift" ]; then
  git diff --stat -- "$fixtures"
  cat <<EOF
check-corpus: the generated fixtures differ from the committed ones:
$drift

A frontend test or a recorded JS module changed the calls the fixtures hold.
Regenerate them, check the Swift ports against them, and commit them:
  node ios-native/tools/gen-json-corpus.mjs
  node ios-native/tools/gen-fixtures.mjs
  (cd ios-native/OpenGymCore && swift test)
  git add $fixtures && git commit
If swift test fails, the JS change needs the same change in the Swift port.
A fixture file git does not track (??) must be committed or deleted.
EOF
  exit 1
fi
