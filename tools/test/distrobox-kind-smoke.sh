#!/usr/bin/env bash
# Smoke test for kind+podman inside distrobox — run from osac-workspace:
#   bash tools/test/distrobox-kind-smoke.sh              # rootless (default)
#   bash tools/test/distrobox-kind-smoke.sh --rootful     # rootful socket
#   bash tools/test/distrobox-kind-smoke.sh --all         # both modes
set -euo pipefail

CLUSTER_NAME="distrobox-smoke-$$"
ROOTFUL=false
ROOTLESS=false

case "${1:-}" in
  --rootful)  ROOTFUL=true ;;
  --all)      ROOTFUL=true; ROOTLESS=true ;;
  *)          ROOTLESS=true ;;
esac

fail() { echo "FAIL: $*" >&2; EXIT_CODE=1; }
pass() { echo "PASS: $*"; }

EXIT_CODE=0

cleanup() {
  for suffix in rootless rootful; do
    kind delete cluster --name "${CLUSTER_NAME}-${suffix}" 2>/dev/null || true
  done
  exit "$EXIT_CODE"
}
trap cleanup EXIT

preflight() {
  command -v podman >/dev/null 2>&1 || { fail "podman not found"; return 1; }
  command -v kind >/dev/null 2>&1   || { fail "kind not found"; return 1; }
  command -v kubectl >/dev/null 2>&1 || { fail "kubectl not found"; return 1; }
  pass "preflight — podman, kind, kubectl available"
}

test_mode() {
  local mode="$1"
  local cluster="${CLUSTER_NAME}-${mode}"
  local env_prefix=()

  if [[ "$mode" == "rootful" ]]; then
    env_prefix=(env PODMAN_ROOTFUL=1)
  fi

  echo "--- Testing ${mode} mode ---"

  # Verify podman responds
  if ! "${env_prefix[@]}" podman info --format '{{.Host.Security.Rootless}}' >/dev/null 2>&1; then
    fail "${mode}: podman info failed — is the ${mode} socket available?"
    return
  fi

  local rootless_val
  rootless_val=$("${env_prefix[@]}" podman info --format '{{.Host.Security.Rootless}}' 2>/dev/null)
  case "$mode" in
    rootless) [[ "$rootless_val" == "true" ]]  || { fail "${mode}: expected Rootless=true, got ${rootless_val}"; return; } ;;
    rootful)  [[ "$rootless_val" == "false" ]] || { fail "${mode}: expected Rootless=false, got ${rootless_val}"; return; } ;;
  esac
  pass "${mode}: podman reports correct security mode"

  # Create kind cluster
  if ! "${env_prefix[@]}" env KIND_EXPERIMENTAL_PROVIDER=podman \
      kind create cluster --name "$cluster" --wait 60s 2>&1; then
    fail "${mode}: kind create cluster failed"
    return
  fi
  pass "${mode}: kind cluster created"

  # Verify kubectl connectivity
  if ! kubectl --context "kind-${cluster}" get nodes >/dev/null 2>&1; then
    fail "${mode}: kubectl cannot reach cluster"
    return
  fi
  pass "${mode}: kubectl can reach cluster"

  # Verify node is Ready
  local retries=12
  while (( retries-- > 0 )); do
    local status
    status=$(kubectl --context "kind-${cluster}" get nodes -o jsonpath='{.items[0].status.conditions[?(@.type=="Ready")].status}' 2>/dev/null || true)
    [[ "$status" == "True" ]] && break
    sleep 5
  done
  if [[ "$status" == "True" ]]; then
    pass "${mode}: node is Ready"
  else
    fail "${mode}: node did not become Ready within 60s"
  fi

  # Cleanup this cluster early
  kind delete cluster --name "$cluster" 2>/dev/null || true
}

preflight || exit 1

if $ROOTLESS; then
  test_mode rootless
fi
if $ROOTFUL; then
  test_mode rootful
fi

if [[ "$EXIT_CODE" -eq 0 ]]; then
  echo "=== All tests passed ==="
else
  echo "=== Some tests failed ==="
fi
exit "$EXIT_CODE"
