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

## Kubernetes (kind)

```bash
kind create cluster
kind load docker-image model-server:local
kubectl apply -f services/model-server/k8s/
kubectl port-forward svc/model-server 8080:80
```

## Phase 2: Local cluster & observability

Prerequisites: Docker Desktop (running), `kind`, and `kubectl` on PATH.

```bash
./scripts/deploy_local.sh
```

This creates the `rollbackops` kind cluster (with host ports 30000/30001 mapped),
builds `model-server:local` if missing, tags it as the manifest image
(`ghcr.io/danial-umer710/rollbackops/model-server:v1.0.0`) and
`kind load`s it — because the Deployment uses `imagePullPolicy: IfNotPresent`,
loading under that exact ref means Kubernetes never tries to pull from ghcr.
It then deploys the model server plus a Prometheus + Grafana stack in the
`monitoring` namespace and runs `scripts/verify_scrape.sh` to confirm metrics
are being scraped.

Endpoints:

- Grafana: http://localhost:30000 (admin/admin, anonymous Viewer enabled)
  with a provisioned "RollbackOps - Model Server" dashboard
- Prometheus: http://localhost:30001

Teardown:

```bash
kind delete cluster --name rollbackops
```
