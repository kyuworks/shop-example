#!/usr/bin/env bash
# Self-test for fetch-engine-compose.sh. Run: bash scripts/fetch-engine-compose.test.sh
# Offline: the "remote" is a file:// directory laid out like raw.githubusercontent.com/kyuworks/kyu.
set -uo pipefail
SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
source "${SCRIPT_DIR}/lib/gate-test-lib.sh"
TMP="$(mktemp -d)"; trap 'rm -rf "${TMP}"' EXIT

# A throwaway checkout: the script, plus an installed @kyuworks/sdk at 9.8.7.
ROOT="${TMP}/shop"
mkdir -p "${ROOT}/scripts" "${ROOT}/node_modules/@kyuworks/sdk"
cp "${SCRIPT_DIR}/fetch-engine-compose.sh" "${ROOT}/scripts/"
printf '{"name":"@kyuworks/sdk","version":"9.8.7"}\n' > "${ROOT}/node_modules/@kyuworks/sdk/package.json"
FETCH="${ROOT}/scripts/fetch-engine-compose.sh"
CACHED="${ROOT}/.cache/kyu-engine/compose.yaml"
REMOTE="${TMP}/remote"

remote_file() {
  mkdir -p "${REMOTE}/$1/infra/hatchet"
  printf '%s' "$2" > "${REMOTE}/$1/infra/hatchet/compose.yaml"
}
GOOD=$'name: kyu-hatchet\nservices:\n  postgres:\n    image: postgres:15.6\n  hatchet-lite:\n    image: ghcr.io/hatchet-dev/hatchet/hatchet-lite:${KYU_HATCHET_IMAGE_TAG:-v0.107.0}\n'
remote_file v9.8.7 "${GOOD}"
remote_file main "${GOOD}# main"
remote_file empty ''
remote_file wrong $'<!DOCTYPE html>\n<html>rate limited</html>\n'

fetch() { KYU_COMPOSE_BASE_URL="file://${REMOTE}" bash "${FETCH}"; }
fetch_ref() { KYU_COMPOSE_REF="$1" KYU_COMPOSE_BASE_URL="file://${REMOTE}" bash "${FETCH}"; }
offline_ref() { KYU_COMPOSE_REF="$1" KYU_COMPOSE_BASE_URL="file://${TMP}/no-network" bash "${FETCH}"; }

echo "=== fetch-engine-compose.sh tests ==="
assert_exit "script exists" 0 test -f "${SCRIPT_DIR}/fetch-engine-compose.sh"

assert_exit "fetches the tag of the installed SDK by default" 0 fetch
assert_same "the cached file is kyu's file at v9.8.7" "${REMOTE}/v9.8.7/infra/hatchet/compose.yaml" "${CACHED}"
assert_eq "records the ref beside the file" "v9.8.7" "$(cat "${ROOT}/.cache/kyu-engine/compose.ref")"
assert_output_lacks "prints nothing on stdout" "kyu" bash -c "KYU_COMPOSE_BASE_URL='file://${REMOTE}' bash '${FETCH}' 2>/dev/null"

assert_exit "KYU_COMPOSE_REF picks another ref" 0 fetch_ref main
assert_same "the cached file is kyu's file at main" "${REMOTE}/main/infra/hatchet/compose.yaml" "${CACHED}"

rm -rf "${ROOT}/.cache"
assert_exit "fails when the download fails and no copy exists" 1 fetch_ref no-such-ref
assert_last_output_contains "names the URL that failed" "no-such-ref/infra/hatchet/compose.yaml"
assert_exit "leaves no file behind after a failed download" 1 test -e "${CACHED}"

fetch_ref v9.8.7 2>/dev/null
assert_exit "fails on an empty body" 1 fetch_ref empty
assert_last_output_contains "says the body was empty" "returned an empty file"
assert_same "an empty body leaves the earlier file in place" "${REMOTE}/v9.8.7/infra/hatchet/compose.yaml" "${CACHED}"
assert_exit "fails on a body that is not a compose file" 1 fetch_ref wrong
assert_last_output_contains "says what was wrong with the body" "not a compose file with a hatchet-lite service"
assert_eq "a wrong body leaves the earlier ref recorded" "v9.8.7" "$(cat "${ROOT}/.cache/kyu-engine/compose.ref")"
assert_eq "no temporary files are left in the cache" "compose.ref compose.yaml" "$(cd "${ROOT}/.cache/kyu-engine" && echo *)"

assert_exit "offline, reuses the copy fetched for the same ref" 0 offline_ref v9.8.7
assert_last_output_contains "says it reused the earlier copy" "reusing the copy fetched earlier for v9.8.7"
assert_exit "offline, refuses a copy fetched for another ref" 1 offline_ref main
assert_last_output_contains "says there is no copy for that ref" "no earlier copy for main"

assert_exit "refuses a ref with characters a ref here may not use" 1 fetch_ref 'v1 ;rm'
rm -f "${ROOT}/node_modules/@kyuworks/sdk/package.json"
assert_exit "fails with no installed SDK and no KYU_COMPOSE_REF" 1 fetch
assert_last_output_contains "says to install first" "run pnpm install first"

gate_test_finish
