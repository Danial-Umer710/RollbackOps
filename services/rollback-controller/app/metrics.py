from prometheus_client import Counter

ROLLBACKS_TOTAL = Counter(
    "rollback_controller_rollbacks_total",
    "Rollbacks attempted by the controller",
    labelnames=["result"],  # executed | already_rolled_back | error
)

DISPATCHES_TOTAL = Counter(
    "rollback_controller_github_dispatches_total",
    "GitHub repository_dispatch audit events",
    labelnames=["result"],  # sent | skipped_no_token | error
)

WEBHOOKS_TOTAL = Counter(
    "rollback_controller_webhooks_total",
    "Alertmanager webhooks received",
    labelnames=["outcome"],  # rollback | ignored
)
