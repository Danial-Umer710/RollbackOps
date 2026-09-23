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
