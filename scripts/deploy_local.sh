#!/usr/bin/env bash
set -euo pipefail

REPO_ROOT="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
CLUSTER_NAME="rollbackops"
INGRESS_NGINX_VERSION="controller-v1.12.1"
INGRESS_NGINX_URL="https://raw.githubusercontent.com/kubernetes/ingress-nginx/${INGRESS_NGINX_VERSION}/deploy/static/provider/kind/deploy.yaml"

for tool in docker kind kubectl; do
  if ! command -v "$tool" >/dev/null 2>&1; then
    echo "ERROR: required tool '$tool' not found on PATH" >&2
    exit 1
  fi
done

# Build (if missing) and load into kind. The local overlay rewrites the
# image refs to <service>:local, so no manifest tagging is needed.
load_image() {
  local local_tag="$1" context_dir="$2"
  if ! docker image inspect "$local_tag" >/dev/null 2>&1; then
    echo "==> Building $local_tag"
    docker build -t "$local_tag" "$context_dir"
  fi
  kind load docker-image "$local_tag" --name "$CLUSTER_NAME"
}

if ! kind get clusters 2>/dev/null | grep -qx "$CLUSTER_NAME"; then
  echo "==> Creating kind cluster '$CLUSTER_NAME'"
  kind create cluster --config "$REPO_ROOT/k8s/kind-config.yaml"
else
  echo "==> Cluster '$CLUSTER_NAME' exists, reusing"
fi

kubectl config use-context "kind-$CLUSTER_NAME"

echo "==> Installing ingress-nginx ($INGRESS_NGINX_VERSION)"
kubectl apply -f "$INGRESS_NGINX_URL"
kubectl -n ingress-nginx rollout status deploy/ingress-nginx-controller --timeout=180s

load_image "model-server:local" "$REPO_ROOT/services/model-server"
load_image "drift-detector:local" "$REPO_ROOT/services/drift-detector"
load_image "rollback-controller:local" "$REPO_ROOT/services/rollback-controller"

if [ -n "${GITHUB_TOKEN:-}" ]; then
  kubectl -n default create secret generic github-token \
    --from-literal=token="$GITHUB_TOKEN" \
    --dry-run=client -o yaml | kubectl apply -f -
  echo "github-token secret applied"
else
  echo "WARNING: GITHUB_TOKEN not set; audit dispatch will be skipped_no_token" >&2
fi

# Single kustomize apply; the retry covers the nginx admission webhook
# returning 500 briefly after the controller becomes ready.
for i in 1 2 3 4 5 6; do
  if kubectl apply -k "$REPO_ROOT/k8s/overlays/local"; then
    break
  fi
  echo "    apply failed (attempt $i/6), retrying in 10s"
  sleep 10
done

kubectl -n default rollout status deploy/model-stable --timeout=120s
kubectl -n default rollout status deploy/model-candidate --timeout=120s
kubectl -n default rollout status deploy/drift-detector --timeout=120s
kubectl -n default rollout status deploy/rollback-controller --timeout=120s
kubectl -n monitoring rollout status deploy/prometheus --timeout=120s
kubectl -n monitoring rollout status deploy/alertmanager --timeout=120s
kubectl -n monitoring rollout status deploy/grafana --timeout=120s
kubectl -n monitoring rollout status deploy/webhook-sink --timeout=120s

# Pick up config/rule changes on a reused cluster (requires --web.enable-lifecycle)
curl -sf -X POST http://localhost:30001/-/reload >/dev/null || true

echo
echo "Grafana:            http://localhost:30000  (admin/admin)"
echo "Prometheus:         http://localhost:30001"
echo "Alertmanager:       http://localhost:30002"
echo "Model API (ingress): http://localhost:8080/predict"
echo

bash "$REPO_ROOT/scripts/verify_scrape.sh"
