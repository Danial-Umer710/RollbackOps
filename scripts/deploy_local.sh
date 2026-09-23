#!/usr/bin/env bash
set -euo pipefail

REPO_ROOT="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
CLUSTER_NAME="rollbackops"

for tool in docker kind kubectl; do
  if ! command -v "$tool" >/dev/null 2>&1; then
    echo "ERROR: required tool '$tool' not found on PATH" >&2
    exit 1
  fi
done

# Build (if missing), tag with the manifest ref, and load into kind.
# The manifest refs must match the image fields in the k8s manifests;
# imagePullPolicy: IfNotPresent means loading under that ref avoids any pull.
load_image() {
  local local_tag="$1" manifest_ref="$2" context_dir="$3"
  if ! docker image inspect "$local_tag" >/dev/null 2>&1; then
    echo "==> Building $local_tag"
    docker build -t "$local_tag" "$context_dir"
  fi
  docker tag "$local_tag" "$manifest_ref"
  kind load docker-image "$manifest_ref" --name "$CLUSTER_NAME"
}

if ! kind get clusters 2>/dev/null | grep -qx "$CLUSTER_NAME"; then
  echo "==> Creating kind cluster '$CLUSTER_NAME'"
  kind create cluster --config "$REPO_ROOT/k8s/kind-config.yaml"
else
  echo "==> Cluster '$CLUSTER_NAME' exists, reusing"
fi

kubectl config use-context "kind-$CLUSTER_NAME"

load_image "model-server:local" \
  "ghcr.io/danial-umer710/rollbackops/model-server:v1.0.0" \
  "$REPO_ROOT/services/model-server"
load_image "drift-detector:local" \
  "ghcr.io/danial-umer710/rollbackops/drift-detector:v0.1.0" \
  "$REPO_ROOT/services/drift-detector"

kubectl apply -f "$REPO_ROOT/services/model-server/k8s/"
kubectl apply -f "$REPO_ROOT/services/drift-detector/k8s/"
kubectl apply -f "$REPO_ROOT/k8s/monitoring/namespace.yaml"
kubectl apply -f "$REPO_ROOT/k8s/monitoring/"

kubectl -n default rollout status deploy/model-stable --timeout=120s
kubectl -n default rollout status deploy/model-candidate --timeout=120s
kubectl -n default rollout status deploy/drift-detector --timeout=120s
kubectl -n monitoring rollout status deploy/prometheus --timeout=120s
kubectl -n monitoring rollout status deploy/alertmanager --timeout=120s
kubectl -n monitoring rollout status deploy/grafana --timeout=120s
kubectl -n monitoring rollout status deploy/webhook-sink --timeout=120s

# Pick up config/rule changes on a reused cluster (requires --web.enable-lifecycle)
curl -sf -X POST http://localhost:30001/-/reload >/dev/null || true

echo
echo "Grafana:      http://localhost:30000  (admin/admin)"
echo "Prometheus:   http://localhost:30001"
echo "Alertmanager: http://localhost:30002"
echo

bash "$REPO_ROOT/scripts/verify_scrape.sh"
