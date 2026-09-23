#!/usr/bin/env bash
set -euo pipefail

PROM="http://localhost:30001"
AM="http://localhost:30002"

echo "==> Checking Prometheus rule ModelDriftDetected"
curl -sf "$PROM/api/v1/rules" | python -c '
import json, sys
data = json.load(sys.stdin)
for group in data.get("data", {}).get("groups", []):
    for rule in group.get("rules", []):
        if rule.get("name") == "ModelDriftDetected":
            print("rule found, state:", rule.get("state"))
            sys.exit(0)
print("ERROR: rule ModelDriftDetected not found", file=sys.stderr)
sys.exit(1)
'

echo "==> Injecting drift via drift-detector"
kubectl -n default port-forward svc/drift-detector 18001:80 >/dev/null 2>&1 &
PF_PID=$!
cleanup() { kill "$PF_PID" >/dev/null 2>&1 || true; }
trap cleanup EXIT

sleep 2
curl -sf -X POST http://localhost:18001/inject-drift \
  -H 'content-type: application/json' -d '{}' | python -m json.tool

echo "==> Waiting for ModelDriftDetected to fire in Prometheus (up to 180s)"
deadline=$((SECONDS + 180))
last_state=""
while true; do
  state=$(curl -sf "$PROM/api/v1/alerts" | python -c '
import json, sys
data = json.load(sys.stdin)
for a in data.get("data", {}).get("alerts", []):
    if a.get("labels", {}).get("alertname") == "ModelDriftDetected":
        print(a.get("state", ""))
        break
' || true)
  if [ "$state" != "$last_state" ] && [ -n "$state" ]; then
    echo "    alert state: $state"
    last_state="$state"
  fi
  if [ "$state" = "firing" ]; then
    break
  fi
  if [ "$SECONDS" -ge "$deadline" ]; then
    echo "ERROR: alert did not reach firing within 180s" >&2
    exit 1
  fi
  sleep 10
done

echo "==> Waiting for alert in Alertmanager (up to 60s)"
deadline=$((SECONDS + 60))
while true; do
  out=$(curl -sf "$AM/api/v2/alerts" | python -c '
import json, sys
alerts = json.load(sys.stdin)
for a in alerts:
    if a.get("labels", {}).get("alertname") == "ModelDriftDetected":
        print(json.dumps(a.get("labels", {}), sort_keys=True))
        break
' || true)
  if [ -n "$out" ]; then
    echo "    Alertmanager labels: $out"
    break
  fi
  if [ "$SECONDS" -ge "$deadline" ]; then
    echo "ERROR: alert not visible in Alertmanager within 60s" >&2
    exit 1
  fi
  sleep 5
done

echo "==> Waiting for webhook-sink to log the alert (up to 60s)"
deadline=$((SECONDS + 60))
while true; do
  if kubectl -n monitoring logs deploy/webhook-sink --since=5m 2>/dev/null \
      | grep -q "RECEIVED alertname=ModelDriftDetected"; then
    kubectl -n monitoring logs deploy/webhook-sink --since=5m \
      | grep "RECEIVED alertname=ModelDriftDetected" | tail -3
    break
  fi
  if [ "$SECONDS" -ge "$deadline" ]; then
    echo "ERROR: webhook-sink did not log ModelDriftDetected within 60s" >&2
    exit 1
  fi
  sleep 5
done

echo "==> Resetting drift"
curl -sf -X POST http://localhost:18001/reset-drift | python -m json.tool

echo "==> Drift alert verification PASSED"
