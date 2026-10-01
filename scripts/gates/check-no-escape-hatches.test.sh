#!/usr/bin/env bash
# Run: bash scripts/gates/check-no-escape-hatches.test.sh
set -uo pipefail
SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
source "${SCRIPT_DIR}/../lib/gate-test-lib.sh"
CHECK="${SCRIPT_DIR}/check-no-escape-hatches.sh"
WORK="$(mktemp -d)"
trap 'rm -rf "${WORK}"' EXIT
echo "=== check-no-escape-hatches tests ==="

mkdir -p "${WORK}/clean/src" "${WORK}/clean/web"
printf 'export const a = 1\n' > "${WORK}/clean/src/a.ts"
printf 'const x = 1 as any\n' > "${WORK}/clean/src/a.test.ts"
printf 'export const w = 1\n' > "${WORK}/clean/web/w.tsx"
printf 'export default {}\n' > "${WORK}/clean/vitest.config.ts"
assert_exit "clean source passes; test files are exempt" 0 env ROOT_DIR="${WORK}/clean" bash "${CHECK}"

mkdir -p "${WORK}/dirty/src"
printf '// @ts-ignore\nexport const b = 1 as unknown as string\n' > "${WORK}/dirty/src/b.ts"
assert_exit "as unknown as / ts-ignore in src fails" 1 env ROOT_DIR="${WORK}/dirty" bash "${CHECK}"
assert_output_contains "failure names the file" "src/b.ts" env ROOT_DIR="${WORK}/dirty" bash "${CHECK}"

mkdir -p "${WORK}/web-dirty/web"
printf 'export const c = 1 as any\n' > "${WORK}/web-dirty/web/c.tsx"
assert_exit "an escape hatch in web fails" 1 env ROOT_DIR="${WORK}/web-dirty" bash "${CHECK}"
assert_output_contains "failure names the web file" "web/c.tsx" env ROOT_DIR="${WORK}/web-dirty" bash "${CHECK}"

mkdir -p "${WORK}/root-dirty/src"
printf 'export const a = 1\n' > "${WORK}/root-dirty/src/a.ts"
printf '// @ts-ignore\nexport const b = 1 as unknown as string\n' > "${WORK}/root-dirty/vitest.integration.setup.ts"
assert_exit "an escape hatch in a root file fails" 1 env ROOT_DIR="${WORK}/root-dirty" bash "${CHECK}"
assert_output_contains "failure names the root file" "vitest.integration.setup.ts" env ROOT_DIR="${WORK}/root-dirty" bash "${CHECK}"

mkdir -p "${WORK}/lint-rules/oxlint-rules" "${WORK}/lint-rules/src"
printf 'export const a = 1\n' > "${WORK}/lint-rules/src/a.ts"
printf '// as unknown as is banned here\nexport const r = 1 as unknown as string\n' > "${WORK}/lint-rules/oxlint-rules/rule.ts"
assert_exit "oxlint-rules is not scanned" 0 env ROOT_DIR="${WORK}/lint-rules" bash "${CHECK}"

# A grep that, like GNU grep given one file operand, omits file names unless -H is passed.
mkdir -p "${WORK}/nameless-grep/bin"
REAL_GREP="$(command -v grep)"
cat > "${WORK}/nameless-grep/bin/grep" <<SH
#!/usr/bin/env bash
for arg in "\$@"; do
  case "\${arg}" in -[a-zA-Z]*H*|--with-filename) exec "${REAL_GREP}" "\$@" ;; esac
done
exec "${REAL_GREP}" "\$@" -h
SH
chmod +x "${WORK}/nameless-grep/bin/grep"

mkdir -p "${WORK}/onefile"
printf 'export const b = 1 as any\n' > "${WORK}/onefile/vite.config.ts"
assert_exit "a one-file search still fails" 1 env PATH="${WORK}/nameless-grep/bin:${PATH}" ROOT_DIR="${WORK}/onefile" bash "${CHECK}"
assert_output_contains "the file is named when grep would omit names" "vite.config.ts" \
  env PATH="${WORK}/nameless-grep/bin:${PATH}" ROOT_DIR="${WORK}/onefile" bash "${CHECK}"

gate_test_finish
