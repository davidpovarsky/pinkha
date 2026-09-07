#!/usr/bin/env bash
set -euo pipefail

ROOT="$(cd "$(dirname "$0")/../../.." && pwd)"
cd "$ROOT"
UDID="${1:?usage: run-torah-ui-tests.sh SIMULATOR_UDID [RESULT_PATH] [focused|full]}"
RESULT="${2:-${TMPDIR:-/tmp}/PinkhaTorahTests.xcresult}"
MODE="${3:-focused}"

ONLY_TESTS=(
  -only-testing:PinkhaUITests/TorahAssociationsUITests
)
if [ "$MODE" = "full" ]; then
  ONLY_TESTS=(
    -only-testing:PinkhaTests
    -only-testing:PinkhaIntegrationTests
    -only-testing:PinkhaUITests
  )
fi

xcodebuild test \
  -project app/Pinkha.xcodeproj \
  -scheme Pinkha \
  -destination "id=$UDID" \
  -resultBundlePath "$RESULT" \
  -parallel-testing-enabled NO \
  "${ONLY_TESTS[@]}"
