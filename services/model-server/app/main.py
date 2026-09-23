import math
import random
import time

import uvicorn
from fastapi import FastAPI, HTTPException, Response
from prometheus_client import CONTENT_TYPE_LATEST, generate_latest
from pydantic import BaseModel, Field

from app.metrics import (
    MODEL_VERSION,
    PREDICTION_LATENCY,
    PREDICTION_SCORE,
    PREDICTIONS_TOTAL,
)

app = FastAPI(title="RollbackOps Model Server")

WEIGHTS = (0.42, -0.17, 0.33, 0.08)
BIAS = -0.05


class PredictRequest(BaseModel):
    features: list[float] = Field(min_length=4, max_length=4)


class PredictResponse(BaseModel):
    prediction: float
    model_version: str
    latency_ms: float


@app.post("/predict", response_model=PredictResponse)
def predict(request: PredictRequest) -> PredictResponse:
    start = time.perf_counter()
    try:
        time.sleep(random.uniform(0.015, 0.045))
        z = sum(w * f for w, f in zip(WEIGHTS, request.features)) + BIAS
        score = 1 / (1 + math.exp(-z))
        score = max(0.0, min(1.0, score))
        PREDICTION_SCORE.observe(score)
        PREDICTIONS_TOTAL.labels(model_version=MODEL_VERSION, status="success").inc()
    except Exception as exc:
        PREDICTIONS_TOTAL.labels(model_version=MODEL_VERSION, status="error").inc()
        raise HTTPException(status_code=500, detail="Inference failed") from exc
    finally:
        PREDICTION_LATENCY.observe(time.perf_counter() - start)
    return PredictResponse(
        prediction=score,
        model_version=MODEL_VERSION,
        latency_ms=(time.perf_counter() - start) * 1000,
    )


@app.get("/healthz")
def healthz() -> dict:
    return {"status": "healthy"}


@app.get("/metrics")
def metrics() -> Response:
    return Response(generate_latest(), media_type=CONTENT_TYPE_LATEST)


if __name__ == "__main__":
    uvicorn.run("app.main:app", host="0.0.0.0", port=8000)
