import json
from dataclasses import dataclass
from typing import Protocol

from app.config import (
    ALB_ACTION_ANNOTATION,
    CANDIDATE_SERVICE,
    CANARY_WEIGHT_ANNOTATION,
    SERVICE_PORT,
    STABLE_SERVICE,
)


class TrafficStrategy(Protocol):
    name: str
    ingress_name: str

    def candidate_weight(self, ingress) -> int:
        """Current % of traffic routed to the candidate."""
        ...

    def rollback_patch(self, ingress) -> dict[str, str]:
        """Annotations that send 100% of traffic to stable."""
        ...


@dataclass
class NginxCanaryStrategy:
    ingress_name: str
    name: str = "nginx"

    def candidate_weight(self, ingress) -> int:
        raw = (ingress.metadata.annotations or {}).get(CANARY_WEIGHT_ANNOTATION, "0")
        try:
            return int(raw)
        except (TypeError, ValueError):
            return 0

    def rollback_patch(self, ingress) -> dict[str, str]:
        return {CANARY_WEIGHT_ANNOTATION: "0"}


@dataclass
class AlbWeightedStrategy:
    ingress_name: str
    stable_service: str = STABLE_SERVICE
    candidate_service: str = CANDIDATE_SERVICE
    service_port: str = SERVICE_PORT
    name: str = "alb"

    def _canonical_action(self) -> dict:
        return {
            "type": "forward",
            "forwardConfig": {
                "targetGroups": [
                    {
                        "serviceName": self.stable_service,
                        "servicePort": self.service_port,
                        "weight": 90,
                    },
                    {
                        "serviceName": self.candidate_service,
                        "servicePort": self.service_port,
                        "weight": 10,
                    },
                ]
            },
        }

    def _action(self, ingress) -> dict:
        raw = (ingress.metadata.annotations or {}).get(ALB_ACTION_ANNOTATION)
        try:
            action = json.loads(raw) if raw else None
        except (TypeError, ValueError):
            action = None
        if (
            not isinstance(action, dict)
            or action.get("type") != "forward"
            or not isinstance(
                action.get("forwardConfig", {}).get("targetGroups"), list
            )
        ):
            return self._canonical_action()
        return action

    def candidate_weight(self, ingress) -> int:
        action = self._action(ingress)
        return sum(
            int(tg.get("weight", 0))
            for tg in action["forwardConfig"]["targetGroups"]
            if tg.get("serviceName") == self.candidate_service
        )

    def rollback_patch(self, ingress) -> dict[str, str]:
        action = self._action(ingress)
        groups = action["forwardConfig"]["targetGroups"]
        has_stable = False
        for tg in groups:
            if tg.get("serviceName") == self.stable_service:
                tg["weight"] = 100
                has_stable = True
            else:
                tg["weight"] = 0
        if not has_stable:
            groups.insert(
                0,
                {
                    "serviceName": self.stable_service,
                    "servicePort": self.service_port,
                    "weight": 100,
                },
            )
        return {ALB_ACTION_ANNOTATION: json.dumps(action, separators=(",", ":"))}


def build_strategy(name: str, ingress_name: str) -> TrafficStrategy:
    if name == "nginx":
        return NginxCanaryStrategy(ingress_name=ingress_name)
    if name == "alb":
        return AlbWeightedStrategy(ingress_name=ingress_name)
    raise ValueError(
        f"unknown TRAFFIC_STRATEGY {name!r}; expected nginx|alb"
    )
