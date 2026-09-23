import logging
from datetime import datetime, timezone

import uvicorn
from fastapi import FastAPI, Response
from fastapi.responses import JSONResponse
from prometheus_client import CONTENT_TYPE_LATEST, generate_latest
from pydantic import BaseModel, ConfigDict

from app.config import CANARY_INGRESS_NAME, CLUSTER_NAME, TARGET_NAMESPACE
from app.github import dispatch_audit_event
from app.k8s import get_networking_api, rollback_canary
from app.metrics import DISPATCHES_TOTAL, ROLLBACKS_TOTAL, WEBHOOKS_TOTAL

logger = logging.getLogger(__name__)
logging.basicConfig(level=logging.INFO)

app = FastAPI(title="RollbackOps Rollback Controller")


def get_api():
    return get_networking_api()


class Alert(BaseModel):
    model_config = ConfigDict(extra="ignore")

    status: str = ""
    labels: dict[str, str] = {}
    annotations: dict[str, str] = {}
    startsAt: str = ""


class WebhookPayload(BaseModel):
    model_config = ConfigDict(extra="ignore")

    status: str = ""
    alerts: list[Alert] = []


def _qualifies(alert: Alert) -> bool:
    return (
        alert.status == "firing"
        and alert.labels.get("alertname") == "ModelDriftDetected"
        and alert.labels.get("action") == "rollback"
    )


@app.post("/webhook")
def webhook(payload: WebhookPayload):
    matching = [a for a in payload.alerts if _qualifies(a)]
    if not matching:
        WEBHOOKS_TOTAL.labels(outcome="ignored").inc()
        return {"handled": False, "reason": "no matching firing alerts"}

    WEBHOOKS_TOTAL.labels(outcome="rollback").inc()
    alert = matching[0]
    model_version = alert.labels.get("model_version", "unknown")
    reason = f"{alert.labels.get('alertname')} model_version={model_version}"

    try:
        result = rollback_canary(
            get_api(), TARGET_NAMESPACE, CANARY_INGRESS_NAME, reason
        )
    except Exception:
        logger.exception("rollback failed")
        ROLLBACKS_TOTAL.labels(result="error").inc()
        return JSONResponse(
            status_code=500, content={"handled": False, "reason": "rollback failed"}
        )

    ROLLBACKS_TOTAL.labels(result=result["result"]).inc()

    dispatch = "skipped"
    if result["result"] in ("executed", "already_rolled_back"):
        audit_payload = {
            "alertname": alert.labels.get("alertname"),
            "model_version": model_version,
            "namespace": TARGET_NAMESPACE,
            "ingress": CANARY_INGRESS_NAME,
            "rollback_result": result["result"],
            "previous_weight": result["previous_weight"],
            "cluster": CLUSTER_NAME,
            "triggered_at": datetime.now(timezone.utc).isoformat(),
            "summary": alert.annotations.get("summary", ""),
        }
        dispatch = dispatch_audit_event(audit_payload)
        DISPATCHES_TOTAL.labels(result=dispatch).inc()

    logger.info(
        "ROLLBACK result=%s model_version=%s previous_weight=%s dispatch=%s",
        result["result"],
        model_version,
        result["previous_weight"],
        dispatch,
    )
    return {"handled": True, "rollback": result, "dispatch": dispatch}


@app.get("/healthz")
def healthz() -> dict:
    return {"status": "healthy"}


@app.get("/metrics")
def metrics() -> Response:
    return Response(generate_latest(), media_type=CONTENT_TYPE_LATEST)


if __name__ == "__main__":
    uvicorn.run("app.main:app", host="0.0.0.0", port=8080)
