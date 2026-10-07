#!/bin/sh
set -eu
cd "$(dirname "$0")/../.."
fixtures=ios-native/OpenGymCore/Tests/OpenGymCoreTests/Fixtures
resources=ios-native/OpenGymApp/Resources
export CHECK_CORPUS_SKIP_GENERATE=1

sh ios-native/tools/check-corpus.sh >/dev/null
probe=
drifted=
trap 'rm -f "$probe"; [ -z "$drifted" ] || git checkout -- "$drifted"' EXIT

expect_untracked_fails() {
  probe=$1
  echo '{}' > "$probe"
  if sh ios-native/tools/check-corpus.sh >/dev/null 2>&1; then
    echo "check-corpus.sh passed with an untracked file: $probe"
    exit 1
  fi
  rm "$probe"
}

expect_drift_fails() {
  drifted=$1
  shift
  echo >> "$drifted"
  if out=$(sh ios-native/tools/check-corpus.sh 2>&1); then
    echo "check-corpus.sh passed with a drifted file: $drifted"
    exit 1
  fi
  git checkout -- "$drifted"
  for expected in "$drifted" "$@" 'swift test' 'git commit'; do
    case "$out" in
      *"$expected"*) ;;
      *) printf 'check-corpus.sh failure does not say "%s":\n%s\n' "$expected" "$out"; exit 1 ;;
    esac
  done
}

expect_exporter_regenerates() {
  drifted=$1
  echo >> "$drifted"
  if ! CHECK_CORPUS_SKIP_GENERATE= CHECK_CORPUS_SKIP_RECORDER=1 sh ios-native/tools/check-corpus.sh >/dev/null 2>&1; then
    echo "check-corpus.sh did not regenerate a drifted file: $drifted"
    exit 1
  fi
  drifted=
}

expect_generator_failure_fails() {
  drifted=frontend/src/locales/th.js
  echo 'export const broken = (' >> "$drifted"
  if CHECK_CORPUS_SKIP_GENERATE= CHECK_CORPUS_SKIP_RECORDER=1 sh ios-native/tools/check-corpus.sh >/dev/null 2>&1; then
    echo "check-corpus.sh passed although convert-locales.mjs crashed on $drifted"
    exit 1
  fi
  git checkout -- "$drifted"
  drifted=
}

expect_exporter_regenerates "$resources/exercises.json"
expect_exporter_regenerates "$resources/Localizable.xcstrings"
expect_generator_failure_fails
expect_untracked_fails "$fixtures/untracked-probe.json"
expect_untracked_fails "$resources/untracked-probe.json"
expect_drift_fails "$fixtures/conformance/rep-range.json" 'node ios-native/tools/gen-fixtures.mjs'
expect_drift_fails "$resources/exercises.json" 'node ios-native/tools/export-exercises.mjs'
expect_drift_fails "$resources/Localizable.xcstrings" 'node ios-native/tools/convert-locales.mjs'
echo "check-corpus.sh: clean tree passes; the exporters regenerate drifted resources; a crashing generator, an untracked or drifted fixture or app resource fails and says how to regenerate"
