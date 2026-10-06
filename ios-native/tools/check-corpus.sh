#!/bin/sh
# Regenerates the JSON corpus and fails unless the result is exactly what is committed.
set -eu
cd "$(dirname "$0")/../.."
fixtures=ios-native/OpenGymCore/Tests/OpenGymCoreTests/Fixtures
node ios-native/tools/gen-json-corpus.mjs
git diff --exit-code --stat -- "$fixtures"
untracked=$(git status --porcelain -- "$fixtures")
if [ -n "$untracked" ]; then
  printf 'fixture files git does not track:\n%s\n' "$untracked"
  exit 1
fi
