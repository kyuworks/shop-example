#!/usr/bin/env bash
# Fail when a workflow's hatchet-lite service image tag differs from the tag
# kyu's compose file pins. Run by .github/workflows/against-kyu-main.yml.
#
#   bash scripts/check-engine-image-tag.sh <kyu compose.yaml> <workflow.yml>...
#
# Self-test: bash scripts/check-engine-image-tag.test.sh
set -euo pipefail

if [ "$#" -lt 2 ]; then
  echo "Usage: $0 <kyu compose.yaml> <workflow.yml>..." >&2
  exit 2
fi
COMPOSE="$1"
shift

# One distinct tag per file, or fail: a file with none or two is not something to compare.
one_tag() {
  local file="$1" pattern="$2" tags
  [ -f "${file}" ] || { echo "FAIL: ${file} not found" >&2; return 1; }
  tags="$(sed -nE "${pattern}" "${file}" | sort -u)"
  if [ -z "${tags}" ]; then
    echo "FAIL: no hatchet-lite image tag found in ${file}" >&2
    return 1
  fi
  if [ "$(printf '%s\n' "${tags}" | wc -l | tr -d ' ')" != "1" ]; then
    echo "FAIL: ${file} pins more than one hatchet-lite tag: $(printf '%s' "${tags}" | tr '\n' ' ')" >&2
    return 1
  fi
  printf '%s' "${tags}"
}

KYU_TAG="$(one_tag "${COMPOSE}" 's#.*hatchet-lite:\$\{KYU_HATCHET_IMAGE_TAG:-([^}]+)\}.*#\1#p')"
status=0
for workflow in "$@"; do
  tag="$(one_tag "${workflow}" "s#^[[:space:]]*image:[[:space:]]*ghcr.io/hatchet-dev/hatchet/hatchet-lite:([^[:space:]'\"]+).*#\1#p")" || { status=1; continue; }
  if [ "${tag}" != "${KYU_TAG}" ]; then
    echo "FAIL: engine image tag mismatch: ${COMPOSE} pins hatchet-lite ${KYU_TAG}, ${workflow} pins hatchet-lite ${tag}" >&2
    status=1
  fi
done
[ "${status}" -eq 0 ] && echo "engine image tag ${KYU_TAG} matches in ${COMPOSE} and $*"
exit "${status}"
