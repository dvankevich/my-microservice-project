#!/usr/bin/env bash
set -euo pipefail

JENKINS_NS="jenkins"
ARGOCD_NS="argocd"
APP_NS="wagtail"
DEV_NS="wagtail-dev"
STAGING_NS="wagtail-staging"
ROLLOUT_TIMEOUT="300s" # Allows up to 5m for Cluster Autoscaler to provision a node if needed

log()  { echo -e "\n\033[1;34m==>\033[0m \033[1m$1\033[0m"; }
pass() { echo -e "\033[1;32m[OK]\033[0m $1"; }
warn() { echo -e "\033[1;33m[WARN]\033[0m $1"; }

usage() {
  cat <<EOF
Usage: $(basename "$0") <command>

Manage CI/CD stack (Jenkins & Argo CD) in EKS without affecting production workloads.

Commands:
  start     Start Jenkins, Argo CD, and Image Updater (refreshes ECR token immediately)
  stop      Scale Jenkins and Argo CD to 0 replicas (preserves EBS data & Application CRDs)
  status    Show current pod/workload status for Jenkins, Argo CD, wagtail, and cluster nodes
  help      Show this help message

Examples:
  $(basename "$0") start
  $(basename "$0") stop
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

cmd_start() {
  check_prerequisites
  log "Active Kubernetes context: ${CONTEXT}"

  # 1. Start Jenkins
  if kubectl get namespace "$JENKINS_NS" &>/dev/null; then
    log "Starting Jenkins in namespace '${JENKINS_NS}'..."
    kubectl scale statefulset --all --replicas=1 -n "$JENKINS_NS"
    kubectl rollout status statefulset/jenkins -n "$JENKINS_NS" --timeout="$ROLLOUT_TIMEOUT"
    pass "Jenkins is Running (https://jenkins.dvankevich.pp.ua)."
  else
    warn "Namespace '${JENKINS_NS}' not found, skipping."
  fi

  # 2. Refresh ECR Credentials & Start Argo CD + Image Updater
  if kubectl get namespace "$ARGOCD_NS" &>/dev/null; then
    log "Starting Argo CD and Image Updater in namespace '${ARGOCD_NS}'..."

    if kubectl get cronjob ecr-token-refresh -n "$ARGOCD_NS" &>/dev/null; then
      kubectl patch cronjob ecr-token-refresh -n "$ARGOCD_NS" -p '{"spec":{"suspend":false}}' >/dev/null
      JOB_NAME="ecr-token-manual-$(date +%s)"
      kubectl create job --from=cronjob/ecr-token-refresh "$JOB_NAME" -n "$ARGOCD_NS" >/dev/null
      pass "Unsuspended 'ecr-token-refresh' and triggered immediate token refresh job '${JOB_NAME}'."
    fi

    kubectl scale statefulset --all --replicas=1 -n "$ARGOCD_NS"
    kubectl scale deployment --all --replicas=1 -n "$ARGOCD_NS"

    log "Waiting for Argo CD deployments and statefulsets to become Ready..."
    for sts in $(kubectl get statefulset -n "$ARGOCD_NS" -o name); do
      kubectl rollout status "$sts" -n "$ARGOCD_NS" --timeout="$ROLLOUT_TIMEOUT"
    done
    for deploy in $(kubectl get deployment -n "$ARGOCD_NS" -o name); do
      kubectl rollout status "$deploy" -n "$ARGOCD_NS" --timeout="$ROLLOUT_TIMEOUT"
    done

    pass "Argo CD is Running (https://argocd.dvankevich.pp.ua)."
  else
    warn "Namespace '${ARGOCD_NS}' not found, skipping."
  fi

  cmd_status
}

cmd_stop() {
  check_prerequisites
  log "Active Kubernetes context: ${CONTEXT}"

  # 1. Stop Jenkins (EBS PVC preserved & orphaned build agents cleaned up)
  if kubectl get namespace "$JENKINS_NS" &>/dev/null; then
    log "Stopping Jenkins in namespace '${JENKINS_NS}'..."
    kubectl scale statefulset --all --replicas=0 -n "$JENKINS_NS"
    kubectl delete pod --all -n "$JENKINS_NS" --ignore-not-found >/dev/null 2>&1 || true
    kubectl wait --for=delete pod --all -n "$JENKINS_NS" --timeout=120s 2>/dev/null || true
    pass "Jenkins scaled to 0 replicas and agent pods removed (EBS volume preserved)."
  else
    warn "Namespace '${JENKINS_NS}' not found, skipping."
  fi

  # 2. Stop Argo CD & Image Updater (Application CRDs untouched)
  if kubectl get namespace "$ARGOCD_NS" &>/dev/null; then
    log "Stopping Argo CD and Image Updater in namespace '${ARGOCD_NS}'..."

    if kubectl get cronjob ecr-token-refresh -n "$ARGOCD_NS" &>/dev/null; then
      kubectl patch cronjob ecr-token-refresh -n "$ARGOCD_NS" -p '{"spec":{"suspend":true}}' >/dev/null
      pass "Suspended CronJob 'ecr-token-refresh'."
    fi

    kubectl scale deployment --all --replicas=0 -n "$ARGOCD_NS"
    kubectl scale statefulset --all --replicas=0 -n "$ARGOCD_NS"
    kubectl wait --for=delete pod --all -n "$ARGOCD_NS" --timeout=120s 2>/dev/null || true
    pass "Argo CD components scaled to 0 replicas (Application CRDs untouched)."
  else
    warn "Namespace '${ARGOCD_NS}' not found, skipping."
  fi

  cmd_status
  pass "CI/CD stack stopped. Cluster Autoscaler will reclaim unneeded nodes after ~10m if minSize allows."
}

cmd_status() {
  check_prerequisites
  log "Cluster & CI/CD Status (context: ${CONTEXT})"

  echo "--- EKS Worker Nodes ---"
  kubectl get nodes --no-headers 2>/dev/null | awk '{printf "%-45s %-10s %s\n", $1, $2, $5}' || true

  echo -e "\n--- Jenkins (${JENKINS_NS}) ---"
  kubectl get statefulset,pods -n "$JENKINS_NS" 2>/dev/null || echo "Namespace '${JENKINS_NS}' not found."

  echo -e "\n--- Argo CD (${ARGOCD_NS}) ---"
  kubectl get deployment,statefulset,pods,cronjob -n "$ARGOCD_NS" 2>/dev/null || echo "Namespace '${ARGOCD_NS}' not found."

  echo -e "\n--- Production App (${APP_NS}) ---"
  kubectl get pods,hpa -n "$APP_NS" 2>/dev/null || echo "Namespace '${APP_NS}' not found."

  echo -e "\n--- Dev App (${DEV_NS}) ---"
  kubectl get pods,deploy -n "$DEV_NS" 2>/dev/null || echo "Namespace '${DEV_NS}' not found."

  echo -e "\n--- Staging App (${STAGING_NS}) ---"
  kubectl get pods,deploy -n "$STAGING_NS" 2>/dev/null || echo "Namespace '${STAGING_NS}' not found."
}

# ------------------------------------------------------------------------------
# Entrypoint
# ------------------------------------------------------------------------------
ACTION="${1:-}"

case "$ACTION" in
  start)
    cmd_start
    ;;
  stop)
    cmd_stop
    ;;
  status)
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
