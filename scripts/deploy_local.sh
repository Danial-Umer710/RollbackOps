#!/usr/bin/env bash
set -euo pipefail

REPO_ROOT="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
CLUSTER_NAME="rollbackops"
LOCAL_IMAGE="model-server:local"
# Must match the image ref in services/model-server/k8s/deployment.yaml
MANIFEST_IMAGE="ghcr.io/danial-umer710/rollbackops/model-server:v1.0.0"

for tool in docker kind kubectl; do
  if ! command -v "$tool" >/dev/null 2>&1; then
    echo "ERROR: required tool '$tool' not found on PATH" >&2
    exit 1
  fi
done

if ! docker image inspect "$LOCAL_IMAGE" >/dev/null 2>&1; then
  echo "==> Building $LOCAL_IMAGE"
  docker build -t "$LOCAL_IMAGE" "$REPO_ROOT/services/model-server"
fi

if ! kind get clusters 2>/dev/null | grep -qx "$CLUSTER_NAME"; then
  echo "==> Creating kind cluster '$CLUSTER_NAME'"
  kind create cluster --config "$REPO_ROOT/k8s/kind-config.yaml"
else
  echo "==> Cluster '$CLUSTER_NAME' exists, reusing"
fi

kubectl config use-context "kind-$CLUSTER_NAME"

# Tag the local image with the manifest ref so IfNotPresent never pulls
docker tag "$LOCAL_IMAGE" "$MANIFEST_IMAGE"
kind load docker-image "$MANIFEST_IMAGE" --name "$CLUSTER_NAME"

kubectl apply -f "$REPO_ROOT/services/model-server/k8s/"
kubectl apply -f "$REPO_ROOT/k8s/monitoring/namespace.yaml"
kubectl apply -f "$REPO_ROOT/k8s/monitoring/"

kubectl -n default rollout status deploy/model-stable --timeout=120s
kubectl -n monitoring rollout status deploy/prometheus --timeout=120s
kubectl -n monitoring rollout status deploy/grafana --timeout=120s

echo
echo "Grafana:    http://localhost:30000  (admin/admin)"
echo "Prometheus: http://localhost:30001"
echo

bash "$REPO_ROOT/scripts/verify_scrape.sh"
