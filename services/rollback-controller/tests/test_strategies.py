import json
from types import SimpleNamespace

import pytest

from app.config import ALB_ACTION_ANNOTATION, CANARY_WEIGHT_ANNOTATION
from app.strategies import (
    AlbWeightedStrategy,
    NginxCanaryStrategy,
    build_strategy,
)


def _ingress(annotations: dict):
    return SimpleNamespace(metadata=SimpleNamespace(annotations=annotations))


def _alb_action(w90=90, w10=10):
    return json.dumps(
        {
            "type": "forward",
            "forwardConfig": {
                "targetGroups": [
                    {"serviceName": "model-server", "servicePort": "80", "weight": w90},
                    {"serviceName": "model-candidate", "servicePort": "80", "weight": w10},
                ]
            },
        }
    )


def _alb():
    return AlbWeightedStrategy(
        ingress_name="model-server",
        stable_service="model-server",
        candidate_service="model-candidate",
        service_port="80",
    )


def test_nginx_candidate_weight():
    s = NginxCanaryStrategy(ingress_name="model-server-canary")
    assert s.candidate_weight(_ingress({CANARY_WEIGHT_ANNOTATION: "10"})) == 10
    assert s.candidate_weight(_ingress({})) == 0
    assert s.candidate_weight(_ingress({CANARY_WEIGHT_ANNOTATION: "junk"})) == 0
    assert s.candidate_weight(_ingress(None)) == 0


def test_nginx_rollback_patch():
    s = NginxCanaryStrategy(ingress_name="model-server-canary")
    assert s.rollback_patch(_ingress({})) == {CANARY_WEIGHT_ANNOTATION: "0"}


def test_alb_candidate_weight():
    s = _alb()
    assert s.candidate_weight(_ingress({ALB_ACTION_ANNOTATION: _alb_action()})) == 10
    assert s.candidate_weight(_ingress({})) == 10  # canonical default
    assert s.candidate_weight(
        _ingress({ALB_ACTION_ANNOTATION: _alb_action(w90=100, w10=0)})
    ) == 0


def test_alb_rollback_patch_sets_weights():
    s = _alb()
    patch = s.rollback_patch(_ingress({ALB_ACTION_ANNOTATION: _alb_action()}))
    action = json.loads(patch[ALB_ACTION_ANNOTATION])
    groups = action["forwardConfig"]["targetGroups"]
    assert action["type"] == "forward"
    assert groups[0]["serviceName"] == "model-server"
    assert groups[0]["weight"] == 100
    assert groups[0]["servicePort"] == "80"
    assert groups[1]["serviceName"] == "model-candidate"
    assert groups[1]["weight"] == 0


def test_alb_malformed_json_uses_canonical():
    s = _alb()
    patch = s.rollback_patch(_ingress({ALB_ACTION_ANNOTATION: "{not json"}))
    groups = json.loads(patch[ALB_ACTION_ANNOTATION])["forwardConfig"]["targetGroups"]
    assert groups[0]["weight"] == 100
    assert groups[1]["weight"] == 0


def test_alb_candidate_only_inserts_stable():
    s = _alb()
    action = json.dumps(
        {
            "type": "forward",
            "forwardConfig": {
                "targetGroups": [
                    {"serviceName": "model-candidate", "servicePort": "80", "weight": 50}
                ]
            },
        }
    )
    patch = s.rollback_patch(_ingress({ALB_ACTION_ANNOTATION: action}))
    groups = json.loads(patch[ALB_ACTION_ANNOTATION])["forwardConfig"]["targetGroups"]
    assert groups[0]["serviceName"] == "model-server"
    assert groups[0]["weight"] == 100
    assert groups[1]["serviceName"] == "model-candidate"
    assert groups[1]["weight"] == 0


def test_build_strategy():
    with pytest.raises(ValueError):
        build_strategy("bogus", "x")
    s = build_strategy("ALB".lower(), "model-server")
    assert isinstance(s, AlbWeightedStrategy)
    assert s.name == "alb"
    assert isinstance(build_strategy("nginx", "model-server-canary"), NginxCanaryStrategy)
