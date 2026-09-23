import os

TARGET_NAMESPACE = os.getenv("TARGET_NAMESPACE", "default")
TRAFFIC_STRATEGY = os.getenv("TRAFFIC_STRATEGY", "nginx").lower()

DEFAULT_INGRESS_NAMES = {
    "nginx": "model-server-canary",
    "alb": "model-server",
}
INGRESS_NAME = (
    os.getenv("INGRESS_NAME")
    or os.getenv("CANARY_INGRESS_NAME")
    or DEFAULT_INGRESS_NAMES.get(TRAFFIC_STRATEGY, "model-server-canary")
)

CANARY_WEIGHT_ANNOTATION = os.getenv(
    "CANARY_WEIGHT_ANNOTATION", "nginx.ingress.kubernetes.io/canary-weight"
)
ALB_ACTION_ANNOTATION = "alb.ingress.kubernetes.io/actions.weighted-routing"
STABLE_SERVICE = os.getenv("STABLE_SERVICE", "model-server")
CANDIDATE_SERVICE = os.getenv("CANDIDATE_SERVICE", "model-candidate")
SERVICE_PORT = os.getenv("SERVICE_PORT", "80")

GITHUB_REPO = os.getenv("GITHUB_REPO", "Danial-Umer710/RollbackOps")
GITHUB_API_URL = os.getenv("GITHUB_API_URL", "https://api.github.com")
GITHUB_TOKEN = os.getenv("GITHUB_TOKEN", "")
CLUSTER_NAME = os.getenv("CLUSTER_NAME", "kind-rollbackops")
