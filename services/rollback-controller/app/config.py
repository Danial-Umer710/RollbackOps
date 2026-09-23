import os

TARGET_NAMESPACE = os.getenv("TARGET_NAMESPACE", "default")
CANARY_INGRESS_NAME = os.getenv("CANARY_INGRESS_NAME", "model-server-canary")
CANARY_WEIGHT_ANNOTATION = os.getenv(
    "CANARY_WEIGHT_ANNOTATION", "nginx.ingress.kubernetes.io/canary-weight"
)
GITHUB_REPO = os.getenv("GITHUB_REPO", "Danial-Umer710/RollbackOps")
GITHUB_API_URL = os.getenv("GITHUB_API_URL", "https://api.github.com")
GITHUB_TOKEN = os.getenv("GITHUB_TOKEN", "")
CLUSTER_NAME = os.getenv("CLUSTER_NAME", "kind-rollbackops")
