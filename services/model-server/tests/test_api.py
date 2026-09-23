import re

from fastapi.testclient import TestClient

from app.main import app

client = TestClient(app)


def test_healthz():
    response = client.get("/healthz")
    assert response.status_code == 200
    assert response.json() == {"status": "healthy"}


def test_predict_valid():
    response = client.post("/predict", json={"features": [0.5, 1.2, -0.3, 2.0]})
    assert response.status_code == 200
    body = response.json()
    assert 0.0 <= body["prediction"] <= 1.0
    assert body["model_version"] == "v1.0.0"
    assert body["latency_ms"] >= 15


def test_predict_rejects_wrong_length():
    response = client.post("/predict", json={"features": [1.0, 2.0]})
    assert response.status_code == 422


def test_predict_rejects_non_numeric():
    response = client.post("/predict", json={"features": ["a", "b", "c", "d"]})
    assert response.status_code == 422


def test_predict_rejects_missing_field():
    response = client.post("/predict", json={})
    assert response.status_code == 422


def _get_counter_value(metrics_text: str) -> float:
    pattern = r'model_predictions_total\{model_version="v1\.0\.0",status="success"\}\s+([\d.eE+]+)'
    match = re.search(pattern, metrics_text)
    return float(match.group(1)) if match else 0.0


def test_metrics_counter_increments():
    before = _get_counter_value(client.get("/metrics").text)
    response = client.post("/predict", json={"features": [0.5, 1.2, -0.3, 2.0]})
    assert response.status_code == 200
    metrics_text = client.get("/metrics").text
    after = _get_counter_value(metrics_text)
    assert after == before + 1
    assert "model_prediction_latency_seconds_bucket" in metrics_text
    assert "model_prediction_score_distribution_bucket" in metrics_text
