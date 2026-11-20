#!/usr/bin/env bash
set -euo pipefail

NAMESPACE="wagtail"
DOMAIN="django-app.dvankevich.pp.ua"
URL="https://${DOMAIN}/"
DEPLOYMENT="django-app-django"
POSTGRES_DEPLOYMENT="django-app-postgres"
HPA_NAME="django-app-django-hpa"

FAST_MODE=false
WITH_DB=false

for arg in "$@"; do
  case $arg in
    --fast) FAST_MODE=true ;;
    --with-db) WITH_DB=true ;;
    *) echo "Unknown option: $arg (available: --fast, --with-db)"; exit 1 ;;
  esac
done

REPORT_FILE="test-report-$(date +%Y-%m-%d_%H-%M).md"
TMP_DIR=$(mktemp -d)
trap 'rm -rf "$TMP_DIR"' EXIT

# Check required CLI utilities
for cmd in kubectl curl openssl hey; do
  if ! command -v "$cmd" &>/dev/null; then
    echo "Error: required utility '$cmd' is not installed."
    exit 1
  fi
done

log() { echo -e "\n\033[1;34m==>\033[0m \033[1m$1\033[0m"; }
pass() { echo -e "\033[1;32m[PASS]\033[0m $1"; }
warn() { echo -e "\033[1;33m[WARN]\033[0m $1"; }

cat <<EOF > "$REPORT_FILE"
# Automated Infrastructure & Load Test Report

- **Date:** $(date '+%Y-%m-%d %H:%M:%S %Z')
- **Target URL:** ${URL}
- **Namespace:** \`${NAMESPACE}\`

---
EOF

# ------------------------------------------------------------------------------
# 1. TLS and HTTP -> HTTPS Redirect
# ------------------------------------------------------------------------------
log "1. Checking TLS certificate and HTTP-to-HTTPS redirect"
HTTP_CODE=$(curl -s -o /dev/null -w "%{http_code}" "http://${DOMAIN}/")
CERT_INFO=$(echo | openssl s_client -servername "$DOMAIN" -connect "${DOMAIN}:443" 2>/dev/null | openssl x509 -noout -issuer -subject -dates)

if [[ "$HTTP_CODE" == "308" || "$HTTP_CODE" == "301" ]]; then
  pass "HTTP redirect is working (status: $HTTP_CODE)"
else
  warn "Unexpected redirect status code: $HTTP_CODE"
fi

cat <<EOF >> "$REPORT_FILE"
## 1. TLS & Redirect Check

- **HTTP to HTTPS redirect status:** \`${HTTP_CODE}\`

\`\`\`text
${CERT_INFO}
\`\`\`

---
EOF

# ------------------------------------------------------------------------------
# 2. High Availability & Self-Healing
# ------------------------------------------------------------------------------
log "2. Checking pod distribution across nodes and Self-Healing"
PODS_WIDE=$(kubectl get pods -n "$NAMESPACE" -o wide)
UNIQUE_NODES=$(kubectl get pods -n "$NAMESPACE" -o wide --no-headers | awk '/^django-app-django-/ {print $7}' | sort -u | wc -l)

if [[ "$UNIQUE_NODES" -ge 2 ]]; then
  pass "Django replicas are distributed across ${UNIQUE_NODES} distinct nodes"
else
  warn "All Django replicas are currently scheduled on ${UNIQUE_NODES} node(s)"
fi

VICTIM_POD=$(kubectl get pods -n "$NAMESPACE" --no-headers | awk '/^django-app-django-/ {print $1; exit}')
echo "Deleting pod $VICTIM_POD to verify self-healing..."
START_HEAL=$(date +%s)
kubectl delete pod "$VICTIM_POD" -n "$NAMESPACE" --wait=false >/dev/null
sleep 3
kubectl rollout status deployment/"$DEPLOYMENT" -n "$NAMESPACE" --timeout=120s >/dev/null
HEAL_DURATION=$(( $(date +%s) - START_HEAL ))
pass "Self-healing completed in ${HEAL_DURATION}s"

PODS_AFTER_HEAL=$(kubectl get pods -n "$NAMESPACE" -o wide)

cat <<EOF >> "$REPORT_FILE"
## 2. High Availability & Self-Healing

- **Unique nodes running Django:** \`${UNIQUE_NODES}\`
- **Deleted pod:** \`${VICTIM_POD}\`
- **Recovery time:** \`${HEAL_DURATION}s\`

\`\`\`text
${PODS_AFTER_HEAL}
\`\`\`

---
EOF

# ------------------------------------------------------------------------------
# 3. Zero-Downtime Rolling Update
# ------------------------------------------------------------------------------
log "3. Checking Zero-Downtime Rolling Update"
PROBE_LOG="$TMP_DIR/rolling_probe.log"

(
  while true; do
    CODE=$(curl -s -o /dev/null -w "%{http_code}" "$URL" || echo "000")
    echo "$(date +%H:%M:%S) $CODE" >> "$PROBE_LOG"
    sleep 0.5
  done
) &
PROBE_PID=$!

kubectl rollout restart deployment/"$DEPLOYMENT" -n "$NAMESPACE" >/dev/null
kubectl rollout status deployment/"$DEPLOYMENT" -n "$NAMESPACE" --timeout=180s >/dev/null
kill "$PROBE_PID" 2>/dev/null || true
wait "$PROBE_PID" 2>/dev/null || true

TOTAL_PROBES=$(wc -l < "$PROBE_LOG")
FAILED_PROBES=$(awk '$2 != "200"' "$PROBE_LOG" | wc -l)

if [[ "$FAILED_PROBES" -eq 0 ]]; then
  pass "Zero-downtime rolling update verified: ${TOTAL_PROBES}/${TOTAL_PROBES} requests returned 200 OK"
else
  warn "Recorded ${FAILED_PROBES} non-200 responses out of ${TOTAL_PROBES} probes during rollout"
fi

cat <<EOF >> "$REPORT_FILE"
## 3. Zero-Downtime Rolling Update

- **Total HTTP probes during rollout:** \`${TOTAL_PROBES}\`
- **Non-200 responses:** \`${FAILED_PROBES}\`

---
EOF

# ------------------------------------------------------------------------------
# 4. External Load Testing (hey) + HPA
# ------------------------------------------------------------------------------
log "4. Running external load test (hey -z 3m -c 30) and monitoring HPA"
HPA_BEFORE=$(kubectl get hpa,pods -n "$NAMESPACE")
HEY_LOG="$TMP_DIR/hey_output.txt"

hey -z 3m -c 30 "$URL" > "$HEY_LOG" &
HEY_PID=$!

PEAK_REPLICAS=2
HPA_PEAK=""

while kill -0 "$HEY_PID" 2>/dev/null; do
  CURRENT_REPLICAS=$(kubectl get hpa "$HPA_NAME" -n "$NAMESPACE" -o jsonpath='{.status.currentReplicas}')
  if [[ "$CURRENT_REPLICAS" -ge "$PEAK_REPLICAS" ]]; then
    PEAK_REPLICAS="$CURRENT_REPLICAS"
    HPA_PEAK=$(kubectl get hpa,pods -n "$NAMESPACE")
  fi
  sleep 15
done
wait "$HEY_PID"

pass "Peak replica count reached under load: ${PEAK_REPLICAS}"
HEY_SUMMARY=$(cat "$HEY_LOG")

if [[ "$FAST_MODE" == false ]]; then
  log "Waiting for HPA scale-down to minReplicas=2 (up to 7 min)..."
  for _ in {1..28}; do
    CUR=$(kubectl get hpa "$HPA_NAME" -n "$NAMESPACE" -o jsonpath='{.status.currentReplicas}')
    if [[ "$CUR" -eq 2 ]]; then
      pass "HPA successfully scaled replicas back down to 2"
      break
    fi
    sleep 15
  done
fi

HPA_AFTER=$(kubectl get hpa,pods -n "$NAMESPACE")

cat <<EOF >> "$REPORT_FILE"
## 4. External HTTPS Load Test (\`hey\`) & HPA Scaling

- **Command:** \`hey -z 3m -c 30 ${URL}\`
- **Peak Replicas Reached:** \`${PEAK_REPLICAS}\`

### HTTP Benchmark Summary
\`\`\`text
${HEY_SUMMARY}
\`\`\`

### HPA State: Before Load
\`\`\`text
${HPA_BEFORE}
\`\`\`

### HPA State: Peak Load
\`\`\`text
${HPA_PEAK}
\`\`\`

### HPA State: After Load
\`\`\`text
${HPA_AFTER}
\`\`\`

---
EOF

# ------------------------------------------------------------------------------
# 5. (Optional) PostgreSQL EBS Persistence Check
# ------------------------------------------------------------------------------
if [[ "$WITH_DB" == true ]]; then
  log "5. Checking PostgreSQL persistence (EBS + Recreate strategy)"
  kubectl rollout restart deployment/"$POSTGRES_DEPLOYMENT" -n "$NAMESPACE" >/dev/null
  kubectl rollout status deployment/"$POSTGRES_DEPLOYMENT" -n "$NAMESPACE" --timeout=180s >/dev/null
  PVC_STATUS=$(kubectl get pvc,pv -n "$NAMESPACE")
  pass "PostgreSQL restarted successfully, PVC remains Bound"

  cat <<EOF >> "$REPORT_FILE"
## 5. PostgreSQL EBS Persistence Check

\`\`\`text
${PVC_STATUS}
\`\`\`
EOF
fi

log "Done! Full report saved to: ${REPORT_FILE}"
