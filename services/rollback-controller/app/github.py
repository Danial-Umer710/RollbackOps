import logging

import httpx

from app.config import GITHUB_API_URL, GITHUB_REPO, GITHUB_TOKEN

logger = logging.getLogger(__name__)


def dispatch_audit_event(payload: dict) -> str:
    if not GITHUB_TOKEN:
        logger.warning("GITHUB_TOKEN not set; skipping audit dispatch")
        return "skipped_no_token"
    try:
        resp = httpx.post(
            f"{GITHUB_API_URL}/repos/{GITHUB_REPO}/dispatches",
            headers={
                "Authorization": f"Bearer {GITHUB_TOKEN}",
                "Accept": "application/vnd.github+json",
                "X-GitHub-Api-Version": "2022-11-28",
            },
            json={
                "event_type": "drift_rollback_triggered",
                "client_payload": payload,
            },
            timeout=10,
        )
    except httpx.HTTPError as exc:
        logger.error("dispatch request failed: %s", exc)
        return "error"
    if resp.status_code == 204:
        return "sent"
    logger.error(
        "dispatch returned status=%s body=%s", resp.status_code, resp.text[:500]
    )
    return "error"
