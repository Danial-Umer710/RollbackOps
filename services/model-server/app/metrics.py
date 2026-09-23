import os

from prometheus_client import Counter, Histogram, Info

MODEL_VERSION = os.getenv("MODEL_VERSION", "v1.0.0")

PREDICTION_LATENCY = Histogram(
    "model_prediction_latency_seconds",
    "Latency of model predictions in seconds",
    buckets=(0.0005, 0.001, 0.0025, 0.005, 0.01, 0.015, 0.02, 0.025,
             0.03, 0.04, 0.05, 0.075, 0.1, 0.25, 0.5, 1.0),
)

PREDICTIONS_TOTAL = Counter(
    "model_predictions_total",
    "Total number of model predictions",
    labelnames=["model_version", "status"],
)

PREDICTION_SCORE = Histogram(
    "model_prediction_score_distribution",
    "Distribution of model prediction scores",
    buckets=(0.1, 0.2, 0.3, 0.4, 0.5, 0.6, 0.7, 0.8, 0.9, 1.0),
)

MODEL_INFO = Info("model", "Model metadata")
MODEL_INFO.info({"version": MODEL_VERSION})
