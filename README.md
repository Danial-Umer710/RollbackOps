# RollbackOps

MLOps platform for safe model rollouts and rollbacks. This repo currently contains
the foundational **model-server** service (`services/model-server`): a FastAPI
inference service that exposes a deterministic mock `/predict` endpoint,
`/healthz` for probes, and Prometheus metrics on `/metrics`.

## Run tests

```bash
cd services/model-server
python -m venv .venv
source .venv/bin/activate  # .venv\Scripts\activate on Windows
pip install -r requirements-dev.txt
python -m pytest -q
```

## Run locally

```bash
cd services/model-server
pip install -r requirements.txt
uvicorn app.main:app --host 0.0.0.0 --port 8000
```

Then: `POST /predict` with `{"features": [0.5, 1.2, -0.3, 2.0]}`,
`GET /healthz`, `GET /metrics`.

## Docker

```bash
docker build -t model-server:local services/model-server
docker run --rm -p 8000:8000 model-server:local
```

## Kubernetes manifests (Kustomize)

Manifests live under `k8s/`: `k8s/base/` contains the environment-agnostic
resources (per-component subdirs), and `k8s/overlays/` holds environment
customizations:

- `k8s/overlays/local` — kind: rewrites images to `<service>:local` and
  re-adds the monitoring NodePorts (Grafana 30000, Prometheus 30001,
  Alertmanager 30002).
- `k8s/overlays/staging` — AWS/EKS: ECR image refs (set by CI via
  `kustomize edit set image`), IRSA annotation for rollback-controller,
  ALB Ingress with weighted-routing (replaces the nginx canary Ingress).

Render without applying: `kubectl kustomize k8s/overlays/local`
(or `.../staging`).

## Kubernetes (kind)

```bash
kind create cluster
kind load docker-image model-server:local
kubectl apply -k k8s/overlays/local
kubectl port-forward svc/model-server 8080:80
```

## Local cluster & observability

Prerequisites: Docker Desktop (running), `kind`, and `kubectl` on PATH.

```bash
./scripts/deploy_local.sh
```

This creates the `rollbackops` kind cluster (with host ports 8080/8443 and
30000/30001/30002 mapped), builds `model-server:local`, `drift-detector:local`
and `rollback-controller:local` if missing, `kind load`s them (the local
overlay points the Deployments at those tags and `imagePullPolicy:
IfNotPresent` means no pull is attempted), and `kubectl apply -k`s
`k8s/overlays/local`. It then deploys:

- `model-stable` (2 replicas, `version=v1.0.0`) and `model-candidate`
  (1 replica, `version=v1.1.0-candidate`, ClusterIP `model-candidate`)
- `drift-detector` — emits `model_drift_score`; `POST /inject-drift` and
  `POST /reset-drift` simulate drift
- monitoring stack in `monitoring`: Prometheus (with the `ModelDriftDetected`
  rule), Alertmanager (routes to `webhook-sink`, a stand-in for the future
  rollback CI trigger), Grafana

and finishes by running `scripts/verify_scrape.sh` to confirm scraping.

Endpoints:

- Grafana: http://localhost:30000 (admin/admin, anonymous Viewer enabled)
  with a provisioned "RollbackOps - Model Server" dashboard
- Prometheus: http://localhost:30001
- Alertmanager: http://localhost:30002

End-to-end drift alert check (inject drift -> Prometheus fires -> Alertmanager
-> webhook-sink logs it -> reset):

```bash
./scripts/verify_drift_alert.sh
```

Note: `k8s/kind-config.yaml` port mappings are baked into the cluster at
creation time — after changing them you must recreate the cluster:

```bash
kind delete cluster --name rollbackops
./scripts/deploy_local.sh
```

Teardown:

```bash
kind delete cluster --name rollbackops
```

## Phase 4: Automated canary rollback

Architecture: `drift-detector` emits `model_drift_score` → Prometheus rule
`ModelDriftDetected` (>0.6 for 1m) → Alertmanager →
`rollback-controller` (`/webhook`) sends 100% of traffic to stable and fires a
GitHub `repository_dispatch` (`drift_rollback_triggered`) →
`.github/workflows/audit.yaml` records the audit.
Alertmanager also mirrors every alert to `webhook-sink` for visibility.

The controller supports two traffic strategies via env:

- `TRAFFIC_STRATEGY=nginx` (default; local overlay sets it explicitly): patches
  `nginx.ingress.kubernetes.io/canary-weight` to `0` on the canary Ingress.
- `TRAFFIC_STRATEGY=alb` (staging overlay): rewrites the
  `alb.ingress.kubernetes.io/actions.weighted-routing` target-group weights to
  100/0 on the main Ingress.

Related env: `INGRESS_NAME` (defaults per strategy — `model-server-canary` for
nginx, `model-server` for alb), `STABLE_SERVICE`/`CANDIDATE_SERVICE`/
`SERVICE_PORT` for the ALB target groups. `GET /strategy` reports the active
strategy.

Traffic reaches the models through ingress-nginx at http://localhost:8080
(kind maps host 8080/8443 -> node 80/443). The canary Ingress sends
`canary-weight: 10`% of `/` traffic to `model-candidate` (`v1.1.0-candidate`);
the rest goes to `model-stable` (`v1.0.0`).

GitHub token (optional): deploy with `export GITHUB_TOKEN=<fine-grained PAT>`
(needs **Contents: read & write** on the repo for `repository_dispatch`). The
deploy script creates the `github-token` Secret from it. Without a token the
rollback still executes; only the audit dispatch is skipped.

```bash
export GITHUB_TOKEN=...   # optional
./scripts/deploy_local.sh
./scripts/verify_rollback.sh
```

`verify_rollback.sh` restores weight 10, proves a mixed-traffic split, injects
drift, waits for the controller to patch the weight to 0, confirms 100% stable
traffic, then resets drift.

Restore the canary afterwards:

```bash
kubectl -n default annotate ingress model-server-canary \
  nginx.ingress.kubernetes.io/canary-weight=10 --overwrite
```

## Infrastructure (OpenTofu + Terragrunt)

AWS IaC lives in `infra/` — see `infra/README.md` (VPC, EKS, ECR, IRSA,
GitHub OIDC; mock-mode `terragrunt plan` works without credentials).
