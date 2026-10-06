#!/bin/sh
# Regenerates the JSON corpus and fails unless the result is exactly what is committed.
set -eu
cd "$(dirname "$0")/../.."
fixtures=ios-native/OpenGymCore/Tests/OpenGymCoreTests/Fixtures
node ios-native/tools/gen-json-corpus.mjs
git diff --exit-code --stat -- "$fixtures"
