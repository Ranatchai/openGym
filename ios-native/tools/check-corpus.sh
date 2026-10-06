#!/bin/sh
set -eu
cd "$(dirname "$0")/../.."
fixtures=ios-native/OpenGymCore/Tests/OpenGymCoreTests/Fixtures
if [ -z "${CHECK_CORPUS_SKIP_GENERATE:-}" ]; then
  node ios-native/tools/gen-json-corpus.mjs
  node ios-native/tools/gen-fixtures.mjs
fi
git diff --exit-code --stat -- "$fixtures"
untracked=$(git status --porcelain -- "$fixtures")
if [ -n "$untracked" ]; then
  printf 'fixture files git does not track:\n%s\n' "$untracked"
  exit 1
fi
