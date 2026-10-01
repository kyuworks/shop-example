#!/usr/bin/env bash
# verify-gates.sh — architecture and process gates, each a script under
# scripts/gates with a colocated *.test.sh. CI sets GITHUB_BASE_SHA; locally the
# migration gate needs BASE_SHA or an origin/main.
set -euo pipefail
cd "$(git rev-parse --show-toplevel)"
echo "[verify:gates] === Gates ==="
for gate in check-required-ci-jobs check-integration-shards check-no-escape-hatches \
  check-durable-wall-clock check-consumer-imports check-migration-immutability; do
  echo "[verify:gates] ${gate}"
  bash "scripts/gates/${gate}.sh"
done
echo "[verify:gates] OK"
