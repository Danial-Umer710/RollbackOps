from datetime import datetime, timezone

from kubernetes import client, config


def get_networking_api() -> client.NetworkingV1Api:
    try:
        config.load_incluster_config()
    except config.ConfigException:
        config.load_kube_config()
    return client.NetworkingV1Api()


def rollback_canary(api, namespace: str, strategy, reason: str) -> dict:
    ingress = api.read_namespaced_ingress(strategy.ingress_name, namespace)
    current = strategy.candidate_weight(ingress)
    if current == 0:
        return {
            "result": "already_rolled_back",
            "previous_weight": "0",
            "strategy": strategy.name,
        }
    api.patch_namespaced_ingress(
        strategy.ingress_name,
        namespace,
        {
            "metadata": {
                "annotations": {
                    **strategy.rollback_patch(ingress),
                    "rollbackops.io/rolled-back-at": datetime.now(
                        timezone.utc
                    ).isoformat(),
                    "rollbackops.io/rollback-reason": reason,
                    "rollbackops.io/previous-canary-weight": str(current),
                    "rollbackops.io/traffic-strategy": strategy.name,
                }
            }
        },
    )
    return {
        "result": "executed",
        "previous_weight": str(current),
        "strategy": strategy.name,
    }
