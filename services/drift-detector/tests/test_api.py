import re

import pytest
from fastapi.testclient import TestClient

from app.main import app


@pytest.fixture()
def client():
    with TestClient(app) as c:
        yield c


def _drift_score(metrics_text: str) -> float:
    pattern = r'model_drift_score\{model_version="v1\.1\.0-candidate"\}\s+([\d.eE+-]+)'
    match = re.search(pattern, metrics_text)
    assert match, "model_drift_score gauge not found in /metrics"
    return float(match.group(1))


def test_healthz(client):
    response = client.get("/healthz")
    assert response.status_code == 200
    assert response.json() == {"status": "healthy"}


def test_metrics_gauge_exists_at_baseline(client):
    response = client.get("/metrics")
    assert response.status_code == 200
    assert 0.05 <= _drift_score(response.text) <= 0.15


def test_inject_drift_default(client):
    response = client.post("/inject-drift")
    assert response.status_code == 200
    body = response.json()
    assert body["mode"] == "injected"
    assert body["model_drift_score"] == 0.85
    assert _drift_score(client.get("/metrics").text) == 0.85


def test_inject_drift_rejects_out_of_range(client):
    response = client.post("/inject-drift", json={"score": 1.5})
    assert response.status_code == 422


def test_reset_drift(client):
    client.post("/inject-drift")
    response = client.post("/reset-drift")
    assert response.status_code == 200
    assert response.json()["mode"] == "baseline"
    assert _drift_score(client.get("/metrics").text) < 0.2


def test_state_reflects_mode(client):
    client.post("/inject-drift")
    state = client.get("/state").json()
    assert state["mode"] == "injected"
    assert state["model_version"] == "v1.1.0-candidate"
    client.post("/reset-drift")
