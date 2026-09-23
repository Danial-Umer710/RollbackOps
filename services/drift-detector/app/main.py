import asyncio
import random
import time
from contextlib import asynccontextmanager

import uvicorn
from fastapi import FastAPI, Response
from prometheus_client import CONTENT_TYPE_LATEST, generate_latest
from pydantic import BaseModel, Field

from app.metrics import (
    BASELINE_SCORE,
    DRIFT_EVALUATIONS,
    DRIFT_SCORE,
    EVAL_INTERVAL_SECONDS,
    INJECTED_SCORE,
    TARGET_MODEL_VERSION,
)


class DriftState:
    def __init__(self) -> None:
        self.mode: str = "baseline"
        self.injected_score: float = INJECTED_SCORE
        self.last_score: float = 0.0
        self.last_evaluated_at: float | None = None


state = DriftState()


def evaluate_once() -> float:
    if state.mode == "injected":
        score = state.injected_score
    else:
        score = BASELINE_SCORE + random.uniform(-0.03, 0.03)
        score = max(0.0, min(1.0, score))
    DRIFT_SCORE.labels(model_version=TARGET_MODEL_VERSION).set(score)
    DRIFT_EVALUATIONS.labels(
        model_version=TARGET_MODEL_VERSION, mode=state.mode
    ).inc()
    state.last_score = score
    state.last_evaluated_at = time.time()
    return score


async def evaluate_loop() -> None:
    while True:
        evaluate_once()
        await asyncio.sleep(EVAL_INTERVAL_SECONDS)


@asynccontextmanager
async def lifespan(app: FastAPI):
    evaluate_once()
    task = asyncio.create_task(evaluate_loop())
    yield
    task.cancel()


app = FastAPI(title="RollbackOps Drift Detector", lifespan=lifespan)


class InjectRequest(BaseModel):
    score: float = Field(default=0.85, ge=0.0, le=1.0)


@app.post("/inject-drift")
def inject_drift(request: InjectRequest | None = None) -> dict:
    if request is not None:
        state.injected_score = request.score
    state.mode = "injected"
    score = evaluate_once()
    return {
        "mode": "injected",
        "model_drift_score": score,
        "model_version": TARGET_MODEL_VERSION,
    }


@app.post("/reset-drift")
def reset_drift() -> dict:
    state.mode = "baseline"
    score = evaluate_once()
    return {
        "mode": "baseline",
        "model_drift_score": score,
        "model_version": TARGET_MODEL_VERSION,
    }


@app.get("/state")
def get_state() -> dict:
    return {
        "mode": state.mode,
        "last_score": state.last_score,
        "model_version": TARGET_MODEL_VERSION,
        "last_evaluated_at": state.last_evaluated_at,
        "baseline_score": BASELINE_SCORE,
    }


@app.get("/healthz")
def healthz() -> dict:
    return {"status": "healthy"}


@app.get("/metrics")
def metrics() -> Response:
    return Response(generate_latest(), media_type=CONTENT_TYPE_LATEST)


if __name__ == "__main__":
    uvicorn.run("app.main:app", host="0.0.0.0", port=8000)
