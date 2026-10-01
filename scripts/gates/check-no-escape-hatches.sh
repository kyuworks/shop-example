#!/usr/bin/env bash
# check-no-escape-hatches.sh — production source may not silence the type
# system or the linter. Tests (*.test.ts, *.test.tsx) are exempt.
#
# Blocked in src/, web/ and the root *.ts files (vitest and vite config):
#   as any | as unknown as | @ts-ignore | @ts-expect-error | eslint-disable | oxlint-disable
#
# Env (tests): ROOT_DIR
set -euo pipefail
ROOT_DIR="${ROOT_DIR:-$(cd "$(dirname "${BASH_SOURCE[0]}")/../.." && pwd)}"
cd "${ROOT_DIR}"
echo "=== no escape hatches ==="
PATTERN='as any\b|as unknown as\b|@ts-ignore|@ts-expect-error|eslint-disable|oxlint-disable'
TARGETS=()
for target in src web; do
  if [ -d "${target}" ]; then TARGETS+=("${target}"); fi
done
for file in ./*.ts; do
  if [ -f "${file}" ]; then TARGETS+=("${file#./}"); fi
done
HITS=""
if [ "${#TARGETS[@]}" -gt 0 ]; then
  HITS="$(grep -rnHE --include='*.ts' --include='*.tsx' --include='*.mts' --exclude='*.test.ts' --exclude='*.test.tsx' --exclude-dir=node_modules --exclude-dir=dist "${PATTERN}" "${TARGETS[@]}" 2>/dev/null || true)"
fi
if [ -n "${HITS}" ]; then
  echo "FAIL: escape hatch in production source:" >&2
  printf '%s\n' "${HITS}" | sed 's/^/  /' >&2
  echo "Fix the type or the code. Do not silence the check." >&2
  exit 1
fi
echo "OK: no escape hatches in src, web or the root config files."
