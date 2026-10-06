#!/bin/sh
# The corpus gate must pass on a clean tree and fail when a fixture file exists that git does not track.
set -eu
cd "$(dirname "$0")/../.."
probe=ios-native/OpenGymCore/Tests/OpenGymCoreTests/Fixtures/untracked-probe.json
trap 'rm -f "$probe"' EXIT
sh ios-native/tools/check-corpus.sh >/dev/null
echo '{}' > "$probe"
if sh ios-native/tools/check-corpus.sh >/dev/null 2>&1; then
  echo "check-corpus.sh passed with an untracked fixture: $probe"
  exit 1
fi
echo "check-corpus.sh: clean tree passes, untracked fixture fails"
