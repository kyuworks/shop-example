#!/usr/bin/env bash
# verify-self-tests.sh — run every *.test.sh under scripts/ and infra/. A new
# self-test is picked up with no registration step. All suites run, so one trip
# reports every broken suite.
set -uo pipefail
# git exports these when it runs a hook; a suite that builds a throwaway repo
# would otherwise commit into the real one.
source "$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)/lib/git-env.sh"
unset "${GIT_HOOK_ENV_VARS[@]}"
ROOT="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
cd "${ROOT}"
failed=()
total=0
while IFS= read -r suite; do
  total=$((total + 1))
  log="$(mktemp)"
  if ! bash "${suite}" >"${log}" 2>&1; then
    failed+=("${suite}")
    echo "FAIL: ${suite}" >&2
    grep -a 'FAIL' "${log}" | head -n 50 >&2
  fi
  rm -f "${log}"
done < <(find scripts infra -name '*.test.sh' | sort)
if [ "${#failed[@]}" -gt 0 ]; then
  echo "FAIL: ${#failed[@]} of ${total} self-test suites failed: ${failed[*]}" >&2
  exit 1
fi
echo "[verify:self-tests] All ${total} suites passed."
