#!/bin/sh
set -eu
cd "$(dirname "$0")/../.."
fixtures=ios-native/OpenGymCore/Tests/OpenGymCoreTests/Fixtures
probe=$fixtures/untracked-probe.json
drifted=$fixtures/conformance/rep-range.json
export CHECK_CORPUS_SKIP_GENERATE=1

sh ios-native/tools/check-corpus.sh >/dev/null
trap 'rm -f "$probe"; git checkout -- "$drifted"' EXIT

echo '{}' > "$probe"
if sh ios-native/tools/check-corpus.sh >/dev/null 2>&1; then
  echo "check-corpus.sh passed with an untracked fixture: $probe"
  exit 1
fi
rm "$probe"

echo >> "$drifted"
if out=$(sh ios-native/tools/check-corpus.sh 2>&1); then
  echo "check-corpus.sh passed with a drifted fixture: $drifted"
  exit 1
fi
for expected in "$drifted" 'node ios-native/tools/gen-fixtures.mjs' 'swift test' 'git commit'; do
  case "$out" in
    *"$expected"*) ;;
    *) printf 'check-corpus.sh failure does not say "%s":\n%s\n' "$expected" "$out"; exit 1 ;;
  esac
done
echo "check-corpus.sh: clean tree passes; an untracked or drifted fixture fails and says how to regenerate"
