import pytest
from fastapi.testclient import TestClient
from kubernetes.client.exceptions import ApiException

import app.github as github_mod
import app.main as main_mod
from app.main import app


class FakeIngressMetadata:
    def __init__(self, annotations):
        self.annotations = annotations


class FakeIngress:
    def __init__(self, weight):
        self.metadata = FakeIngressMetadata(
            {"nginx.ingress.kubernetes.io/canary-weight": weight}
        )


class FakeNetworkingApi:
    def __init__(self, weight="10", raise_on_read=False):
        self.weight = weight
        self.raise_on_read = raise_on_read
        self.patch_calls = []

    def read_namespaced_ingress(self, name, namespace):
        if self.raise_on_read:
            raise ApiException(status=500, reason="boom")
        return FakeIngress(self.weight)

    def patch_namespaced_ingress(self, name, namespace, body):
        self.patch_calls.append((name, namespace, body))
        return FakeIngress("0")


def _payload(alertname="ModelDriftDetected", status="firing", action="rollback"):
    return {
        "status": status,
        "alerts": [
            {
                "status": status,
                "labels": {
                    "alertname": alertname,
                    "action": action,
                    "model_version": "v1.1.0-candidate",
                },
                "annotations": {"summary": "drift!"},
                "startsAt": "2026-01-01T00:00:00Z",
            }
        ],
    }


@pytest.fixture()
def client():
    return TestClient(app)


@pytest.fixture()
def fake_api(monkeypatch):
    api = FakeNetworkingApi()
    monkeypatch.setattr(main_mod, "get_api", lambda: api)
    return api


@pytest.fixture()
def dispatch_spy(monkeypatch):
    calls = []
    monkeypatch.setattr(main_mod, "dispatch_audit_event", lambda p: calls.append(p) or "sent")
    return calls


def test_non_matching_alert_ignored(client, fake_api, dispatch_spy):
    resp = client.post("/webhook", json=_payload(alertname="OtherAlert"))
    assert resp.status_code == 200
    assert resp.json()["handled"] is False
    assert fake_api.patch_calls == []
    assert dispatch_spy == []


def test_resolved_alert_ignored(client, fake_api, dispatch_spy):
    resp = client.post("/webhook", json=_payload(status="resolved"))
    assert resp.status_code == 200
    assert resp.json()["handled"] is False
    assert fake_api.patch_calls == []


def test_firing_alert_executes_rollback(client, fake_api, dispatch_spy):
    resp = client.post("/webhook", json=_payload())
    assert resp.status_code == 200
    body = resp.json()
    assert body["handled"] is True
    assert body["rollback"]["result"] == "executed"
    assert body["rollback"]["previous_weight"] == "10"
    assert len(fake_api.patch_calls) == 1
    annotations = fake_api.patch_calls[0][2]["metadata"]["annotations"]
    assert annotations["nginx.ingress.kubernetes.io/canary-weight"] == "0"
    assert annotations["rollbackops.io/previous-canary-weight"] == "10"
    assert len(dispatch_spy) == 1
    assert dispatch_spy[0]["model_version"] == "v1.1.0-candidate"


def test_already_rolled_back(client, monkeypatch, dispatch_spy):
    api = FakeNetworkingApi(weight="0")
    monkeypatch.setattr(main_mod, "get_api", lambda: api)
    resp = client.post("/webhook", json=_payload())
    assert resp.status_code == 200
    assert resp.json()["rollback"]["result"] == "already_rolled_back"
    assert api.patch_calls == []
    assert len(dispatch_spy) == 1


def test_k8s_error_returns_500(client, monkeypatch, dispatch_spy):
    api = FakeNetworkingApi(raise_on_read=True)
    monkeypatch.setattr(main_mod, "get_api", lambda: api)
    resp = client.post("/webhook", json=_payload())
    assert resp.status_code == 500
    assert dispatch_spy == []


def test_dispatch_skipped_without_token(monkeypatch):
    monkeypatch.setattr(github_mod, "GITHUB_TOKEN", "")
    called = []
    monkeypatch.setattr(github_mod.httpx, "post", lambda *a, **k: called.append(1))
    assert github_mod.dispatch_audit_event({"x": 1}) == "skipped_no_token"
    assert called == []


def test_dispatch_sends_bearer_and_event_type(monkeypatch):
    captured = {}

    class FakeResp:
        status_code = 204
        text = ""

    def fake_post(url, headers=None, json=None, timeout=None):
        captured.update(url=url, headers=headers, json=json)
        return FakeResp()

    monkeypatch.setattr(github_mod, "GITHUB_TOKEN", "tok123")
    monkeypatch.setattr(github_mod.httpx, "post", fake_post)
    assert github_mod.dispatch_audit_event({"k": "v"}) == "sent"
    assert captured["headers"]["Authorization"] == "Bearer tok123"
    assert captured["json"]["event_type"] == "drift_rollback_triggered"
    assert captured["json"]["client_payload"] == {"k": "v"}
