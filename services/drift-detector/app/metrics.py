import os

from prometheus_client import Counter, Gauge

TARGET_MODEL_VERSION = os.getenv("TARGET_MODEL_VERSION", "v1.1.0-candidate")

DRIFT_SCORE = Gauge(
    "model_drift_score",
    "Data drift score for the monitored model (0 = no drift, 1 = severe)",
    labelnames=["model_version"],
)

DRIFT_EVALUATIONS = Counter(
    "drift_evaluations_total",
    "Number of drift evaluations performed",
    labelnames=["model_version", "mode"],
)

BASELINE_SCORE = float(os.getenv("DRIFT_BASELINE_SCORE", "0.1"))
INJECTED_SCORE = 0.85
EVAL_INTERVAL_SECONDS = float(os.getenv("DRIFT_EVAL_INTERVAL_SECONDS", "10"))
