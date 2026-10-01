#!/usr/bin/env bash
# verify-gates.sh — architecture and process gates, each a script under
# scripts/gates with a colocated *.test.sh. CI sets GITHUB_BASE_SHA and, on a pull
# request, PR_BODY_FILE; locally the migration gate needs BASE_SHA or an origin/main.
set -euo pipefail
cd "$(git rev-parse --show-toplevel)"
echo "[verify:gates] === Gates ==="
for gate in check-required-ci-jobs check-integration-shards check-no-escape-hatches \
  check-durable-wall-clock check-consumer-imports check-migration-immutability; do
  echo "[verify:gates] ${gate}"
  bash "scripts/gates/${gate}.sh"
done
if [ -n "${PR_BODY_FILE:-}" ]; then
  echo "[verify:gates] check-agent-ship-loop"
  bash scripts/gates/check-agent-ship-loop.sh --body "${PR_BODY_FILE}" --author "${PR_AUTHOR:-}" --branch "${PR_BRANCH:-}"
else
  echo "[verify:gates] check-agent-ship-loop skipped: PR_BODY_FILE is not set (CI sets it on a pull request)"
fi
echo "[verify:gates] OK"
