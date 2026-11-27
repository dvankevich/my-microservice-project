#!/usr/bin/env bash
set -euo pipefail

ARGOCD_NS="argocd"
PROD_NS="wagtail"
DEV_NS="wagtail-dev"
STAGING_NS="wagtail-staging"
DEV_APP="django-app-dev"
STAGING_APP="django-app-staging"
DEV_DEPLOY="django-app-dev-django"
STAGING_DEPLOY="django-app-staging-django"
ROLLOUT_TIMEOUT="300s"

log()  { echo -e "\n\033[1;34m==>\033[0m \033[1m$1\033[0m"; }
pass() { echo -e "\033[1;32m[OK]\033[0m $1"; }
warn() { echo -e "\033[1;33m[WARN]\033[0m $1"; }

usage() {
  cat <<EOF
Usage: $(basename "$0") <command> [dev|staging]

Scale the dev and staging Django apps without touching production.
Argo CD selfHeal would undo a plain 'kubectl scale', so stop/start also
sets or removes the Helm parameter replicaCount on the Application.

Commands:
  start     Run the selected apps with 1 replica (default: dev and staging)
  stop      Scale the selected apps to 0 replicas (default: dev and staging)
  status    Show dev, staging, and production deployments
  help      Show this help message

Examples:
  $(basename "$0") stop
  $(basename "$0") start dev
  $(basename "$0") status
EOF
}

check_prerequisites() {
  if ! command -v kubectl &>/dev/null; then
    echo "Error: 'kubectl' is not installed or not in PATH." >&2
    exit 1
  fi

  CONTEXT=$(kubectl config current-context 2>/dev/null || true)
  if [[ -z "$CONTEXT" ]]; then
    echo "Error: no active kubectl context found." >&2
    exit 1
  fi
}

selected_envs() {
  case "${1:-all}" in
    all|"")
      printf '%s\n' dev staging
      ;;
    dev|staging)
      printf '%s\n' "$1"
      ;;
    *)
      echo "Error: unknown environment '$1'. Expected dev, staging, or no argument." >&2
      exit 1
      ;;
  esac
}

env_app() {
  case "$1" in
    dev) printf '%s\n' "$DEV_APP" ;;
    staging) printf '%s\n' "$STAGING_APP" ;;
  esac
}

env_namespace() {
  case "$1" in
    dev) printf '%s\n' "$DEV_NS" ;;
    staging) printf '%s\n' "$STAGING_NS" ;;
  esac
}

env_deploy() {
  case "$1" in
    dev) printf '%s\n' "$DEV_DEPLOY" ;;
    staging) printf '%s\n' "$STAGING_DEPLOY" ;;
  esac
}

parameter_index() {
  local app="$1"
  local wanted="$2"
  local i=0
  local name
  local found=""

  while IFS= read -r name; do
    [[ -z "$name" ]] && continue
    if [[ "$name" == "$wanted" ]]; then
      found="$i"
      break
    fi
    i=$((i + 1))
  done < <(kubectl get application "$app" -n "$ARGOCD_NS" -o jsonpath='{range .spec.source.helm.parameters[*]}{.name}{"\n"}{end}' 2>/dev/null || true)

  printf '%s\n' "$found"
}

set_replica_parameter() {
  local app="$1"
  local replicas="$2"
  local idx

  if ! kubectl get application "$app" -n "$ARGOCD_NS" &>/dev/null; then
    warn "Application '${app}' not found in '${ARGOCD_NS}'. Argo CD can scale it back on the next sync."
    return 0
  fi

  idx="$(parameter_index "$app" replicaCount)"
  if [[ -n "$idx" ]]; then
    kubectl patch application "$app" -n "$ARGOCD_NS" --type json \
      -p "[{\"op\":\"replace\",\"path\":\"/spec/source/helm/parameters/${idx}/value\",\"value\":\"${replicas}\"}]" >/dev/null
  else
    kubectl patch application "$app" -n "$ARGOCD_NS" --type json \
      -p "[{\"op\":\"add\",\"path\":\"/spec/source/helm/parameters/-\",\"value\":{\"name\":\"replicaCount\",\"value\":\"${replicas}\"}}]" >/dev/null
  fi
  pass "Application '${app}' helm replicaCount=${replicas}."
}

clear_replica_parameter() {
  local app="$1"
  local idx

  if ! kubectl get application "$app" -n "$ARGOCD_NS" &>/dev/null; then
    warn "Application '${app}' not found in '${ARGOCD_NS}', skipping."
    return 0
  fi

  idx="$(parameter_index "$app" replicaCount)"
  if [[ -z "$idx" ]]; then
    pass "Application '${app}' has no replicaCount override."
    return 0
  fi

  kubectl patch application "$app" -n "$ARGOCD_NS" --type json \
    -p "[{\"op\":\"remove\",\"path\":\"/spec/source/helm/parameters/${idx}\"}]" >/dev/null
  pass "Removed replicaCount override from Application '${app}'."
}

scale_deployment() {
  local namespace="$1"
  local deploy="$2"
  local replicas="$3"

  if ! kubectl get namespace "$namespace" &>/dev/null; then
    warn "Namespace '${namespace}' not found, skipping."
    return 0
  fi
  if ! kubectl get deployment "$deploy" -n "$namespace" &>/dev/null; then
    warn "Deployment '${deploy}' not found in '${namespace}', skipping."
    return 0
  fi

  kubectl scale deployment "$deploy" -n "$namespace" --replicas="$replicas" >/dev/null
  if [[ "$replicas" == "0" ]]; then
    kubectl wait --for=delete pod -l "app=${deploy}" -n "$namespace" --timeout=120s >/dev/null 2>&1 || true
    pass "Deployment '${deploy}' in '${namespace}' scaled to 0."
  else
    kubectl rollout status "deployment/${deploy}" -n "$namespace" --timeout="$ROLLOUT_TIMEOUT"
    pass "Deployment '${deploy}' in '${namespace}' is running."
  fi
}

cmd_stop() {
  local env app namespace deploy
  check_prerequisites
  log "Active Kubernetes context: ${CONTEXT}"
  log "Stopping ${*} (production namespace '${PROD_NS}' is not changed)."

  for env in "$@"; do
    app="$(env_app "$env")"
    namespace="$(env_namespace "$env")"
    deploy="$(env_deploy "$env")"
    log "Stopping ${env} (${namespace}/${deploy})..."
    set_replica_parameter "$app" 0
    scale_deployment "$namespace" "$deploy" 0
  done

  cmd_status
}

cmd_start() {
  local env app namespace deploy
  check_prerequisites
  log "Active Kubernetes context: ${CONTEXT}"
  log "Starting ${*} with 1 replica."

  for env in "$@"; do
    app="$(env_app "$env")"
    namespace="$(env_namespace "$env")"
    deploy="$(env_deploy "$env")"
    log "Starting ${env} (${namespace}/${deploy})..."
    clear_replica_parameter "$app"
    scale_deployment "$namespace" "$deploy" 1
  done

  cmd_status
}

cmd_status() {
  check_prerequisites
  log "Dev and staging status (context: ${CONTEXT})"

  echo "--- Production (${PROD_NS}, not managed by this script) ---"
  kubectl get deploy -n "$PROD_NS" 2>/dev/null || echo "Namespace '${PROD_NS}' not found."

  echo -e "\n--- Dev (${DEV_NS}) ---"
  kubectl get deploy,pods -n "$DEV_NS" 2>/dev/null || echo "Namespace '${DEV_NS}' not found."
  echo "replicaCount override: $(replica_override "$DEV_APP")"

  echo -e "\n--- Staging (${STAGING_NS}) ---"
  kubectl get deploy,pods -n "$STAGING_NS" 2>/dev/null || echo "Namespace '${STAGING_NS}' not found."
  echo "replicaCount override: $(replica_override "$STAGING_APP")"
}

replica_override() {
  local value
  value="$(kubectl get application "$1" -n "$ARGOCD_NS" -o jsonpath='{.spec.source.helm.parameters[?(@.name=="replicaCount")].value}' 2>/dev/null || true)"
  printf '%s\n' "${value:-none}"
}

ACTION="${1:-}"
TARGET="${2:-all}"

case "$ACTION" in
  start)
    # shellcheck disable=SC2046
    cmd_start $(selected_envs "$TARGET")
    ;;
  stop)
    # shellcheck disable=SC2046
    cmd_stop $(selected_envs "$TARGET")
    ;;
  status)
    if [[ -n "${2:-}" ]]; then
      echo "Error: status does not take an environment argument." >&2
      exit 1
    fi
    cmd_status
    ;;
  help|-h|--help)
    usage
    exit 0
    ;;
  "")
    echo "Error: missing command." >&2
    echo ""
    usage
    exit 1
    ;;
  *)
    echo "Error: unknown command '$ACTION'." >&2
    echo ""
    usage
    exit 1
    ;;
esac
