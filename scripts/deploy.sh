#!/usr/bin/env bash
###############################################################
# scripts/deploy.sh
# Helm deployment script for PwC Azure Banking Platform
# Usage: ./scripts/deploy.sh <environment> <image_tag>
###############################################################

set -euo pipefail
IFS=$'\n\t'

# ---------------------------------------------------------------------------
# Constants
# ---------------------------------------------------------------------------
readonly SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
readonly PROJECT_ROOT="${SCRIPT_DIR}/.."
readonly NAMESPACE="banking"
readonly HELM_CHART="${PROJECT_ROOT}/helm/banking-api"
readonly RELEASE_NAME="banking-api"
readonly TIMEOUT="15m"
readonly HISTORY_MAX=5

# ---------------------------------------------------------------------------
# Colours for output
# ---------------------------------------------------------------------------
RED='\033[0;31m'; GREEN='\033[0;32m'; YELLOW='\033[1;33m'; NC='\033[0m'
log()   { echo -e "${GREEN}[$(date +'%H:%M:%S')] INFO: ${NC}$*"; }
warn()  { echo -e "${YELLOW}[$(date +'%H:%M:%S')] WARN: ${NC}$*"; }
error() { echo -e "${RED}[$(date +'%H:%M:%S')] ERROR: ${NC}$*" >&2; exit 1; }

# ---------------------------------------------------------------------------
# Input validation
# ---------------------------------------------------------------------------
ENVIRONMENT="${1:-}"
IMAGE_TAG="${2:-}"

[[ -z "$ENVIRONMENT" ]] && error "Usage: $0 <environment> <image_tag>"
[[ -z "$IMAGE_TAG" ]]   && error "Usage: $0 <environment> <image_tag>"

case "$ENVIRONMENT" in
  dev|staging|prod) ;;
  *) error "Invalid environment: $ENVIRONMENT. Must be dev, staging, or prod." ;;
esac

VALUES_FILE="${HELM_CHART}/values-${ENVIRONMENT}.yaml"
[[ ! -f "$VALUES_FILE" ]] && VALUES_FILE="${HELM_CHART}/values.yaml"

# ---------------------------------------------------------------------------
# Pre-flight checks
# ---------------------------------------------------------------------------
preflight_checks() {
  log "Running pre-flight checks..."

  command -v helm    >/dev/null 2>&1 || error "helm not found in PATH"
  command -v kubectl >/dev/null 2>&1 || error "kubectl not found in PATH"
  command -v az      >/dev/null 2>&1 || error "az CLI not found in PATH"

  # Ensure AKS context is set
  local current_context
  current_context=$(kubectl config current-context 2>/dev/null) || \
    error "kubectl context not set. Run: az aks get-credentials ..."

  log "Current kubectl context: ${current_context}"

  # Verify namespace exists
  kubectl get namespace "${NAMESPACE}" >/dev/null 2>&1 || {
    warn "Namespace '${NAMESPACE}' does not exist. Creating..."
    kubectl create namespace "${NAMESPACE}"
    kubectl label namespace "${NAMESPACE}" \
      environment="${ENVIRONMENT}" \
      compliance="fca:pci-dss:iso27001"
  }

  log "Pre-flight checks passed."
}

# ---------------------------------------------------------------------------
# Health check — ensure cluster is healthy before deploying
# ---------------------------------------------------------------------------
pre_deployment_health_check() {
  log "Running pre-deployment health check..."

  local unhealthy_pods
  unhealthy_pods=$(kubectl get pods -n "${NAMESPACE}" \
    --field-selector="status.phase!=Running,status.phase!=Succeeded,status.phase!=Pending" \
    --no-headers 2>/dev/null | wc -l)

  if [[ "$unhealthy_pods" -gt 0 ]]; then
    warn "Detected ${unhealthy_pods} unhealthy pod(s) in ${NAMESPACE}:"
    kubectl get pods -n "${NAMESPACE}" \
      --field-selector="status.phase!=Running,status.phase!=Succeeded"
    if [[ "$ENVIRONMENT" == "prod" ]]; then
      error "Aborting production deployment due to unhealthy pods."
    fi
    warn "Proceeding with non-prod deployment despite unhealthy pods."
  fi

  log "Pre-deployment health check passed."
}

# ---------------------------------------------------------------------------
# Helm deploy
# ---------------------------------------------------------------------------
helm_deploy() {
  log "Deploying ${RELEASE_NAME}:${IMAGE_TAG} to ${ENVIRONMENT}..."

  helm upgrade --install "${RELEASE_NAME}" "${HELM_CHART}" \
    --namespace "${NAMESPACE}" \
    --values "${HELM_CHART}/values.yaml" \
    --values "${VALUES_FILE}" \
    --set "image.tag=${IMAGE_TAG}" \
    --set "image.repository=acrpwcbankingprod.azurecr.io/banking-api" \
    --wait \
    --timeout "${TIMEOUT}" \
    --atomic \
    --cleanup-on-fail \
    --history-max "${HISTORY_MAX}" \
    2>&1 | tee /tmp/helm-deploy-${ENVIRONMENT}.log

  log "Helm deployment completed successfully."
}

# ---------------------------------------------------------------------------
# Post-deployment verification
# ---------------------------------------------------------------------------
post_deployment_verification() {
  log "Running post-deployment verification..."

  # Wait for rollout to complete
  kubectl rollout status deployment/"${RELEASE_NAME}" \
    -n "${NAMESPACE}" \
    --timeout=300s

  # Verify minimum pods are running (PDB requirement)
  local available_pods
  available_pods=$(kubectl get deployment "${RELEASE_NAME}" -n "${NAMESPACE}" \
    -o jsonpath='{.status.availableReplicas}' 2>/dev/null || echo 0)

  local min_pods=3
  if [[ "${available_pods}" -lt "${min_pods}" ]]; then
    error "Only ${available_pods}/${min_pods} pods available after deployment."
  fi

  log "Post-deployment verification passed. ${available_pods} pods running."
}

# ---------------------------------------------------------------------------
# Smoke tests
# ---------------------------------------------------------------------------
run_smoke_tests() {
  if [[ ! -f "${SCRIPT_DIR}/smoke-tests.py" ]]; then
    warn "smoke-tests.py not found. Skipping smoke tests."
    return 0
  fi

  log "Running smoke tests..."
  local base_url

  case "$ENVIRONMENT" in
    dev)     base_url="https://api-dev.banking.internal" ;;
    staging) base_url="https://api-staging.banking.internal" ;;
    prod)    base_url="https://api.banking.internal" ;;
  esac

  python3 "${SCRIPT_DIR}/smoke-tests.py" \
    --base-url "${base_url}" \
    --timeout 30 \
    --mode health-only

  log "Smoke tests passed."
}

# ---------------------------------------------------------------------------
# Main
# ---------------------------------------------------------------------------
main() {
  log "=== PwC Banking Platform Deployment ==="
  log "Environment : ${ENVIRONMENT}"
  log "Image Tag   : ${IMAGE_TAG}"
  log "Namespace   : ${NAMESPACE}"
  log "======================================="

  preflight_checks
  pre_deployment_health_check
  helm_deploy
  post_deployment_verification
  run_smoke_tests

  log "=== Deployment complete: ${RELEASE_NAME}:${IMAGE_TAG} → ${ENVIRONMENT} ==="
}

main "$@"
