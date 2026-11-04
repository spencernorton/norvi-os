# Session journal

## 2026-11-03 — Bound CI status checks and superseded PR work

Bound the final CI status job to five minutes while retaining every required upstream result. Cancel superseded pull-request runs by PR number; give non-PR and reusable workflow runs separate groups so they can finish independently. Validation: actionlint, workflow structure checks and the required native pull-request checks.

