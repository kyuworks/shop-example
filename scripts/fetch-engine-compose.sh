#!/usr/bin/env bash
# Download kyu's engine compose file into .cache/kyu-engine/compose.yaml, for
# `pnpm hatchet:up`, `pnpm hatchet:down` and infra/hatchet/token.sh.
# The ref is the tag of the installed @kyuworks/sdk (v<version>); KYU_COMPOSE_REF overrides it.
# Offline, it reuses a file fetched earlier for the same ref. Messages go to stderr only.
#
# Self-test: bash scripts/fetch-engine-compose.test.sh
set -euo pipefail
ROOT="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
BASE_URL="${KYU_COMPOSE_BASE_URL:-https://raw.githubusercontent.com/kyuworks/kyu}"
CACHE_DIR="${ROOT}/.cache/kyu-engine"
SDK_PACKAGE_JSON="${ROOT}/node_modules/@kyuworks/sdk/package.json"
COMPOSE="${CACHE_DIR}/compose.yaml"
REF_FILE="${CACHE_DIR}/compose.ref"

fail() {
  echo "fetch-engine-compose: FAIL: $*" >&2
  exit 1
}

REF="${KYU_COMPOSE_REF:-}"
if [ -z "${REF}" ]; then
  [ -f "${SDK_PACKAGE_JSON}" ] || fail "${SDK_PACKAGE_JSON} not found; run pnpm install first, or set KYU_COMPOSE_REF"
  REF="v$(node -e 'process.stdout.write(JSON.parse(require("node:fs").readFileSync(process.argv[1], "utf8")).version)' "${SDK_PACKAGE_JSON}")"
fi
case "${REF}" in
  ''|*[!A-Za-z0-9._/-]*|*..*|/*|-*) fail "ref '${REF}' has characters or a shape a git ref here may not use" ;;
esac
URL="${BASE_URL}/${REF}/infra/hatchet/compose.yaml"

mkdir -p "${CACHE_DIR}"
TMP="$(mktemp "${CACHE_DIR}/compose.yaml.XXXXXX")"
trap 'rm -f "${TMP}" "${TMP}.ref"' EXIT

if ! curl -fsSL --path-as-is --proto-redir =https --connect-timeout 10 --max-time 60 -o "${TMP}" "${URL}"; then
  if [ -f "${COMPOSE}" ] && [ -f "${REF_FILE}" ] && [ "$(cat "${REF_FILE}")" = "${REF}" ]; then
    echo "fetch-engine-compose: could not download ${URL}; reusing the copy fetched earlier for ${REF}" >&2
    exit 0
  fi
  fail "could not download ${URL}, and there is no earlier copy for ${REF}"
fi
[ -s "${TMP}" ] || fail "${URL} returned an empty file"
grep -q '^services:' "${TMP}" && grep -q '^  hatchet-lite:' "${TMP}" \
  || fail "${URL} is not a compose file with a hatchet-lite service"

# The ref file goes last, so a half-finished update is never taken for the old ref.
rm -f "${REF_FILE}"
mv "${TMP}" "${COMPOSE}"
printf '%s\n' "${REF}" > "${TMP}.ref"
mv "${TMP}.ref" "${REF_FILE}"
echo "fetch-engine-compose: ${COMPOSE} is kyu's compose file at ${REF}" >&2
