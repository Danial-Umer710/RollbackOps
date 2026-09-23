#!/usr/bin/env bash
set -euo pipefail

echo "==> Generating traffic against model-server"
kubectl -n default port-forward svc/model-server 18000:80 >/dev/null 2>&1 &
PF_PID=$!
cleanup() { kill "$PF_PID" >/dev/null 2>&1 || true; }
trap cleanup EXIT

sleep 2
curl -sf http://localhost:18000/healthz >/dev/null
for i in 1 2 3 4 5; do
  curl -sf -X POST http://localhost:18000/predict \
    -H 'content-type: application/json' \
    -d '{"features":[0.5,1.2,-0.3,2.0]}' >/dev/null
  echo "    prediction $i sent"
done

echo "==> Polling Prometheus for model_predictions_total (up to 90s)"
deadline=$((SECONDS + 90))
while true; do
  result=$(curl -sf 'http://localhost:30001/api/v1/query' \
    --data-urlencode 'query=sum(model_predictions_total{job="model-server"})' || true)
  if [ -n "$result" ] && printf '%s' "$result" | python -c '
import json, sys
data = json.load(sys.stdin)
res = data.get("data", {}).get("result", [])
sys.exit(0 if res and float(res[0]["value"][1]) > 0 else 1)
'; then
    echo "==> Prometheus is scraping model-server:"
    printf '%s\n' "$result" | python -m json.tool
    break
  fi
  if [ "$SECONDS" -ge "$deadline" ]; then
    echo "ERROR: timed out waiting for model_predictions_total{job=\"model-server\"} > 0" >&2
    echo "Check: kubectl -n monitoring logs deploy/prometheus" >&2
    exit 1
  fi
  sleep 5
done

echo "==> Active scrape targets:"
curl -s 'http://localhost:30001/api/v1/targets' | python -c '
import json, sys
data = json.load(sys.stdin)
for t in data.get("data", {}).get("activeTargets", []):
    job = t.get("labels", {}).get("job", "?")
    print("{:20} {:45} {}".format(job, t["scrapeUrl"], t["health"]))
'
