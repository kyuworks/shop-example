#!/usr/bin/env bash
# Self-test for check-engine-image-tag.sh. Run: bash scripts/check-engine-image-tag.test.sh
set -uo pipefail
SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
ROOT="$(cd "${SCRIPT_DIR}/.." && pwd)"
source "${SCRIPT_DIR}/lib/gate-test-lib.sh"
CHECK="${SCRIPT_DIR}/check-engine-image-tag.sh"
TMP="$(mktemp -d)"; trap 'rm -rf "${TMP}"' EXIT

compose_with_tag() {
  printf 'services:\n  hatchet-lite:\n    image: ghcr.io/hatchet-dev/hatchet/hatchet-lite:${KYU_HATCHET_IMAGE_TAG:-%s}\n' "$1" > "$2"
}
workflow_with_tag() {
  printf 'jobs:\n  t:\n    services:\n      hatchet-lite:\n        image: ghcr.io/hatchet-dev/hatchet/hatchet-lite:%s\n' "$1" > "$2"
}
compose_with_tag v0.107.0 "${TMP}/compose.yaml"
{ cat "${TMP}/compose.yaml"; printf '  pgbouncer:\n    image: edoburu/pgbouncer:v1.25.2-p0\n# a new comment\n'; } > "${TMP}/compose-more.yaml"
compose_with_tag v0.108.0 "${TMP}/compose-new.yaml"
workflow_with_tag v0.107.0 "${TMP}/ci.yml"
workflow_with_tag v0.107.0 "${TMP}/daily.yml"
workflow_with_tag v0.106.0 "${TMP}/daily-old.yml"
printf 'jobs: {}\n' > "${TMP}/no-engine.yml"
{ cat "${TMP}/ci.yml"; printf '      other:\n        image: ghcr.io/hatchet-dev/hatchet/hatchet-lite:v0.1.0\n'; } > "${TMP}/two-tags.yml"

echo "=== check-engine-image-tag.sh tests ==="
assert_exit "script exists" 0 test -f "${CHECK}"
assert_exit "passes when every tag matches" 0 bash "${CHECK}" "${TMP}/compose.yaml" "${TMP}/ci.yml" "${TMP}/daily.yml"
assert_exit "passes when kyu's file changes everything but the engine tag" 0 bash "${CHECK}" "${TMP}/compose-more.yaml" "${TMP}/ci.yml"

assert_exit "fails when kyu moves to a new engine tag" 1 bash "${CHECK}" "${TMP}/compose-new.yaml" "${TMP}/ci.yml"
assert_last_output_contains "names kyu's tag" "pins hatchet-lite v0.108.0"
assert_last_output_contains "names this repository's tag" "${TMP}/ci.yml pins hatchet-lite v0.107.0"
assert_exit "fails when one of several workflows differs" 1 bash "${CHECK}" "${TMP}/compose.yaml" "${TMP}/ci.yml" "${TMP}/daily-old.yml"
assert_last_output_contains "names the workflow that differs" "daily-old.yml pins hatchet-lite v0.106.0"

assert_exit "fails on a workflow with no engine image" 1 bash "${CHECK}" "${TMP}/compose.yaml" "${TMP}/no-engine.yml"
assert_last_output_contains "says no tag was found" "no hatchet-lite image tag found in ${TMP}/no-engine.yml"
assert_exit "fails on a compose file with no engine image" 1 bash "${CHECK}" "${TMP}/no-engine.yml" "${TMP}/ci.yml"
assert_exit "fails on a workflow with two engine tags" 1 bash "${CHECK}" "${TMP}/compose.yaml" "${TMP}/two-tags.yml"
assert_last_output_contains "says there is more than one tag" "pins more than one hatchet-lite tag"
assert_exit "fails on a missing file" 1 bash "${CHECK}" "${TMP}/compose.yaml" "${TMP}/absent.yml"
assert_exit "fails with no workflow argument" 2 bash "${CHECK}" "${TMP}/compose.yaml"

# This repository's two workflows agree with each other, read the same way the daily run reads them.
workflow_tag="$(sed -nE "s#^[[:space:]]*image:[[:space:]]*ghcr.io/hatchet-dev/hatchet/hatchet-lite:([^[:space:]'\"]+).*#\1#p" "${ROOT}/.github/workflows/ci.yml" | head -1)"
compose_with_tag "${workflow_tag}" "${TMP}/compose-ours.yaml"
assert_exit "ci.yml and against-kyu-main.yml pin the same engine tag" 0 \
  bash "${CHECK}" "${TMP}/compose-ours.yaml" "${ROOT}/.github/workflows/ci.yml" "${ROOT}/.github/workflows/against-kyu-main.yml"

gate_test_finish
