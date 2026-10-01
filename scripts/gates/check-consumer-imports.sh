#!/usr/bin/env bash
# check-consumer-imports.sh — the shop is a consumer of the published SDK, so it
# imports `@kyuworks/sdk` and nothing else from the bus.
#
# Blocked in src/, web/ and the root *.ts files (tests included, they are part
# of the consumer proof). Every import form counts: `from`, bare
# `import '...'`, dynamic `import('...')`, `require('...')`, for the deep imports too.
#   @hatchet-dev/...                     consume @kyuworks/sdk only
#   @kyuworks/schemas                    consume @kyuworks/sdk only
#   @kyuworks/<pkg>/src/... or /dist/... deep import past the exports map
# The same two packages are blocked as dependencies in package.json.
#
# Env (tests): ROOT_DIR
set -euo pipefail
ROOT_DIR="${ROOT_DIR:-$(cd "$(dirname "${BASH_SOURCE[0]}")/../.." && pwd)}"
cd "${ROOT_DIR}"
echo "=== consumer imports ==="
FAIL=0
TARGETS=()
for target in src web; do
  if [ -d "${target}" ]; then TARGETS+=("${target}"); fi
done
for file in ./*.ts; do
  if [ -f "${file}" ]; then TARGETS+=("${file#./}"); fi
done
GREP=(grep -rnHE --include='*.ts' --include='*.tsx' --include='*.mts' --exclude-dir=node_modules --exclude-dir=dist)

if [ "${#TARGETS[@]}" -gt 0 ]; then
  MODSPEC="@hatchet-dev/[^'\"]*|@kyuworks/schemas([^'\"]*)?"
  BANNED_PATTERN="(from|import)[[:space:]]+['\"](${MODSPEC})['\"]|(import|require)[[:space:]]*\([[:space:]]*['\"](${MODSPEC})['\"]"
  BANNED="$("${GREP[@]}" "${BANNED_PATTERN}" "${TARGETS[@]}" 2>/dev/null || true)"
  if [ -n "${BANNED}" ]; then
    printf '%s\n' "${BANNED}" | sed 's/^/FAIL: consume @kyuworks\/sdk only: /' >&2
    FAIL=1
  fi
  DEEPSPEC="@kyuworks/[a-z0-9-]+/(src|dist)/"
  DEEP_PATTERN="(from|import)[[:space:]]+['\"]${DEEPSPEC}|(import|require)[[:space:]]*\([[:space:]]*['\"]${DEEPSPEC}"
  DEEP="$("${GREP[@]}" "${DEEP_PATTERN}" "${TARGETS[@]}" 2>/dev/null || true)"
  if [ -n "${DEEP}" ]; then
    printf '%s\n' "${DEEP}" | sed 's/^/FAIL: deep import past the exports map: /' >&2
    FAIL=1
  fi
fi

if [ -f package.json ]; then
  BANNED_DEPS="$(node -e '
    const pkg = JSON.parse(require("node:fs").readFileSync("package.json", "utf8"));
    const deps = { ...pkg.dependencies, ...pkg.devDependencies };
    for (const name of Object.keys(deps)) {
      if (name.startsWith("@hatchet-dev/") || name === "@kyuworks/schemas") console.log(`package.json: ${name}`);
    }
  ')"
  if [ -n "${BANNED_DEPS}" ]; then
    printf '%s\n' "${BANNED_DEPS}" | sed 's/^/FAIL: consume @kyuworks\/sdk only: /' >&2
    FAIL=1
  fi
fi

if [ "${FAIL}" -ne 0 ]; then
  echo "Import @kyuworks/sdk by name. If it lacks something, ask for it in kyuworks/kyu." >&2
  exit 1
fi
echo "OK: the shop imports @kyuworks/sdk only."
