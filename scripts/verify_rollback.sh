#!/usr/bin/env bash
set -euo pipefail

ING_API="http://localhost:8080"
WEIGHT_JSONPATH='{.metadata.annotations.nginx\.ingress\.kubernetes\.io/canary-weight}'

post_predict() {
  curl -sf -X POST "$ING_API/predict" \
    -H 'content-type: application/json' \
    -d '{"features":[0.5,1.2,-0.3,2.0]}'
}

tally_versions() {
  local n="$1" i
  for i in $(seq "$n"); do
    post_predict | python -c 'import json,sys; print(json.load(sys.stdin)["model_version"])'
  done | sort | uniq -c
}

echo "==> Checking rollback-controller strategy"
kubectl -n default port-forward svc/rollback-controller 18002:8080 >/dev/null 2>&1 &
RC_PF_PID=$!
sleep 2
STRATEGY_JSON=$(curl -sf http://localhost:18002/strategy)
echo "    $STRATEGY_JSON"
printf '%s' "$STRATEGY_JSON" | python -c '
import json, sys
s = json.load(sys.stdin)
assert s["strategy"] == "nginx", f"expected nginx strategy, got {s}"
'
kill "$RC_PF_PID" >/dev/null 2>&1 || true

echo "==> Restoring canary weight to 10"
kubectl -n default annotate ingress model-server-canary \
  nginx.ingress.kubernetes.io/canary-weight=10 --overwrite
sleep 3

echo "==> Sending 60 requests (pre-rollback split)"
before=$(tally_versions 60)
echo "$before"
printf '%s\n' "$before" | grep -q "v1.0.0" || { echo "ERROR: no v1.0.0 responses" >&2; exit 1; }
printf '%s\n' "$before" | grep -q "v1.1.0-candidate" || { echo "ERROR: no candidate responses at weight 10" >&2; exit 1; }

echo "==> Injecting drift"
kubectl -n default port-forward svc/drift-detector 18001:80 >/dev/null 2>&1 &
PF_PID=$!
cleanup() { kill "$PF_PID" >/dev/null 2>&1 || true; }
trap cleanup EXIT
sleep 2
curl -sf -X POST http://localhost:18001/inject-drift \
  -H 'content-type: application/json' -d '{}' | python -m json.tool

echo "==> Waiting for canary weight to become 0 (up to 180s)"
deadline=$((SECONDS + 180))
last=""
while true; do
  w=$(kubectl -n default get ingress model-server-canary -o "jsonpath=$WEIGHT_JSONPATH" 2>/dev/null || true)
  if [ "$w" != "$last" ]; then
    echo "    canary-weight: ${w:-<unset>}"
    last="$w"
  fi
  [ "$w" = "0" ] && break
  if [ "$SECONDS" -ge "$deadline" ]; then
    echo "ERROR: canary weight did not reach 0 within 180s" >&2
    exit 1
  fi
  sleep 5
done

echo "==> rollback-controller log:"
kubectl -n default logs deploy/rollback-controller --since=10m | grep "ROLLBACK" | tail -5
kubectl -n default logs deploy/rollback-controller --since=10m \
  | grep -q "ROLLBACK result=executed" \
  || { echo "ERROR: no 'ROLLBACK result=executed' log line" >&2; exit 1; }

echo "==> Sending 40 requests (post-rollback, expect 100% v1.0.0)"
after=$(tally_versions 40)
echo "$after"
if printf '%s\n' "$after" | grep -qv "v1\.0\.0$"; then
  echo "ERROR: non-stable responses after rollback" >&2
  exit 1
fi

echo "==> Rollback annotations on model-server-canary:"
kubectl -n default get ingress model-server-canary -o json \
  | python -c '
import json, sys
ann = json.load(sys.stdin)["metadata"]["annotations"]
for k, v in sorted(ann.items()):
    if k.startswith("rollbackops.io/") or "canary" in k or "traffic-strategy" in k:
        print(f"  {k}: {v}")
'

echo "==> Resetting drift"
curl -sf -X POST http://localhost:18001/reset-drift | python -m json.tool

echo
echo "==> Rollback verification PASSED"
echo "To restore the canary: kubectl -n default annotate ingress model-server-canary \\"
echo "  nginx.ingress.kubernetes.io/canary-weight=10 --overwrite"
