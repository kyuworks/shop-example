#!/usr/bin/env bash
# Run: bash scripts/gates/check-consumer-imports.test.sh
set -uo pipefail
SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
source "${SCRIPT_DIR}/../lib/gate-test-lib.sh"
CHECK="${SCRIPT_DIR}/check-consumer-imports.sh"
WORK="$(mktemp -d)"
trap 'rm -rf "${WORK}"' EXIT
echo "=== check-consumer-imports tests ==="

# fixture <name> <relative path> <content>: a repo with that one source file.
fixture() {
  mkdir -p "${WORK}/$1/$(dirname "$2")"
  printf '%s\n' "$3" > "${WORK}/$1/$2"
  [ -f "${WORK}/$1/package.json" ] || printf '{"dependencies":{"@kyuworks/sdk":"^0.1.0"}}\n' > "${WORK}/$1/package.json"
}
run() { env ROOT_DIR="${WORK}/$1" bash "${CHECK}"; }

fixture clean src/a.ts "import { kyu } from '@kyuworks/sdk'"
assert_exit "an import of @kyuworks/sdk passes" 0 run clean

fixture hatchet src/a.ts "import { Hatchet } from '@hatchet-dev/typescript-sdk'"
assert_exit "a from-import of @hatchet-dev fails" 1 run hatchet
assert_output_contains "the offending file is named" "src/a.ts" run hatchet

fixture bare src/a.test.ts "import '@kyuworks/schemas'"
assert_exit "a bare import of @kyuworks/schemas in a test fails" 1 run bare

fixture dynamic web/a.tsx "const m = await import('@kyuworks/schemas/envelope')"
assert_exit "a dynamic import of @kyuworks/schemas in web fails" 1 run dynamic

fixture required vitest.config.ts "const m = require('@hatchet-dev/typescript-sdk')"
assert_exit "a require in a root file fails" 1 run required
assert_output_contains "the root file is named" "vitest.config.ts" run required

fixture deep src/a.ts "import { x } from '@kyuworks/sdk/dist/index.js'"
assert_exit "a deep import past the exports map fails" 1 run deep

fixture deepdyn src/a.ts "const m = await import('@kyuworks/sdk/dist/index.js')"
assert_exit "a dynamic deep import past the exports map fails" 1 run deepdyn

fixture deepreq src/a.ts "const m = require('@kyuworks/sdk/src/index')"
assert_exit "a require deep import past the exports map fails" 1 run deepreq

fixture deepbare src/a.ts "import '@kyuworks/sdk/dist/register.js'"
assert_exit "a bare deep import past the exports map fails" 1 run deepbare

fixture dep src/a.ts "export const a = 1"
printf '{"dependencies":{"@kyuworks/sdk":"^0.1.0","@kyuworks/schemas":"^0.1.0"}}\n' > "${WORK}/dep/package.json"
assert_exit "@kyuworks/schemas as a dependency fails" 1 run dep
assert_output_contains "the dependency is named" "@kyuworks/schemas" run dep

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

fixture onefile vitest.config.ts "const m = require('@hatchet-dev/typescript-sdk')"
assert_exit "a one-file search still fails" 1 env PATH="${WORK}/nameless-grep/bin:${PATH}" ROOT_DIR="${WORK}/onefile" bash "${CHECK}"
assert_output_contains "the file is named when grep would omit names" "vitest.config.ts" \
  env PATH="${WORK}/nameless-grep/bin:${PATH}" ROOT_DIR="${WORK}/onefile" bash "${CHECK}"

gate_test_finish
