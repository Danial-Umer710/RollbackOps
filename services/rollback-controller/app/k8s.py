from datetime import datetime, timezone

from kubernetes import client, config

from app.config import CANARY_WEIGHT_ANNOTATION


def get_networking_api() -> client.NetworkingV1Api:
    try:
        config.load_incluster_config()
    except config.ConfigException:
        config.load_kube_config()
    return client.NetworkingV1Api()


def rollback_canary(api, namespace: str, ingress_name: str, reason: str) -> dict:
    ingress = api.read_namespaced_ingress(ingress_name, namespace)
    current = (ingress.metadata.annotations or {}).get(CANARY_WEIGHT_ANNOTATION, "0")
    if current == "0":
        return {"result": "already_rolled_back", "previous_weight": "0"}
    api.patch_namespaced_ingress(
        ingress_name,
        namespace,
        {
            "metadata": {
                "annotations": {
                    CANARY_WEIGHT_ANNOTATION: "0",
                    "rollbackops.io/rolled-back-at": datetime.now(
                        timezone.utc
                    ).isoformat(),
                    "rollbackops.io/rollback-reason": reason,
                    "rollbackops.io/previous-canary-weight": current,
                }
            }
        },
    )
    return {"result": "executed", "previous_weight": current}
