#!/usr/bin/env bash

set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
REPO_ROOT="$(cd "${SCRIPT_DIR}/../../../.." && pwd)"
INFRA_DIR="${REPO_ROOT}/ecs-infra"
ALLOWED_INGRESS_CIDR="${ALLOWED_INGRESS_CIDR:-203.0.113.10/32}"

info() {
  printf 'info: %s\n' "$1"
}

ok() {
  printf 'ok: %s\n' "$1"
}

warn() {
  printf 'warn: %s\n' "$1"
}

fail() {
  printf 'error: %s\n' "$1" >&2
  exit 1
}

require_file() {
  local path="$1"
  [ -f "$path" ] || fail "Missing required file: ${path}"
}

count_template_resources() {
  local template="$1"

  node -e '
    const fs = require("node:fs");
    const template = JSON.parse(fs.readFileSync(process.argv[1], "utf8"));
    console.log(Object.keys(template.Resources ?? {}).length);
  ' "$template"
}

info "Validating ecs-infra CDK workspace"
info "Repository root: ${REPO_ROOT}"
info "allowedIngressCidr: ${ALLOWED_INGRESS_CIDR}"

require_file "${REPO_ROOT}/package.json"
require_file "${INFRA_DIR}/package.json"
require_file "${INFRA_DIR}/cdk.json"

command -v npm >/dev/null 2>&1 || fail "npm is required"
command -v node >/dev/null 2>&1 || fail "node is required"

info "Running TypeScript build"
npm -w ecs-infra run build
ok "TypeScript build passed"

info "Running CDK assertion tests"
npm -w ecs-infra test
ok "CDK tests passed"

info "Synthesizing CloudFormation"
rm -rf "${INFRA_DIR}/cdk.out"
npm -w ecs-infra run cdk -- synth -c "allowedIngressCidr=${ALLOWED_INGRESS_CIDR}" --quiet >/dev/null
ok "CDK synth passed"

template_count=0
while IFS= read -r -d '' template; do
  template_count=$((template_count + 1))
  resource_count="$(count_template_resources "$template")"
  template_size="$(wc -c < "$template")"
  stack_name="$(basename "$template" .template.json)"

  info "${stack_name}: ${resource_count} resources, ${template_size} bytes"

  if [ "$resource_count" -gt 200 ]; then
    warn "${stack_name}: high resource count; consider splitting stacks when this becomes hard to review"
  fi

  if [ "$template_size" -gt 51200 ]; then
    warn "${stack_name}: template is larger than 50 KB; watch for reviewability and CloudFormation limits"
  fi
done < <(find "${INFRA_DIR}/cdk.out" -name "*.template.json" -print0 2>/dev/null)

if [ "$template_count" -eq 0 ]; then
  fail "No synthesized templates found in ${INFRA_DIR}/cdk.out"
fi

if ! rg -q '"cdk-nag"|cdk-nag' "${INFRA_DIR}/package.json"; then
  warn "cdk-nag is not installed. That is acceptable for the current wave, but consider it before production-like hardening."
fi

ok "ecs-infra validation passed"
