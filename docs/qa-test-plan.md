---
layout: default
title: QA Test Plan
---

# QA Test Plan

Automated end-to-end verification of the Stadium Wallet stack across both clusters. The script `scripts/qa-test-plan.sh` validates GitOps sync, service mesh, API security, rate limiting, observability, and cross-cluster availability in a single run.

---

## Test flow

```
                          ┌──────────────┐
                          │   Hub cluster │  (oc context)
                          │   QA script   │
                          └──────┬───────┘
                                 │
                 ┌───────────────┴───────────────┐
                 │                               │
          ┌──────▼──────┐                 ┌──────▼──────┐
          │  East cluster│                 │  West cluster│
          │  dev / test  │                 │  dev / test  │
          │  prod        │                 │  prod        │
          └─────────────┘                 └─────────────┘
```

1. The script runs from a machine with `oc` authenticated to the **hub** cluster.
2. Tests that require the Kubernetes API (QA-01, QA-02) query the hub via `oc`.
3. Tests that verify HTTP endpoints (QA-03 through QA-10) use `curl` against the east and west cluster Routes directly — no tunnel or VPN required, only HTTPS access to `*.apps.<cluster-domain>`.
4. Environment variables `EAST_DOMAIN` and `WEST_DOMAIN` tell the script which clusters to hit; defaults are the current sandbox domains.

---

## Prerequisites

| Requirement | Detail |
|-------------|--------|
| `oc` CLI | Authenticated to the **hub** cluster (`oc whoami` = hub). Needed for QA-01, QA-02. Set `SKIP_OC=1` to skip these. |
| `curl` | Used by all HTTP tests (QA-03 through QA-10). |
| HTTPS access | Outbound HTTPS to `*.apps.<EAST_DOMAIN>` and `*.apps.<WEST_DOMAIN>`. |
| API keys | Default keys are baked in (`nfl-wallet-customers-key`, etc.). Override with `API_KEY_*` env vars if your secrets differ. |

---

## Usage

```bash
# Run all 10 tests (oc context = hub)
./scripts/qa-test-plan.sh

# Run specific tests only
./scripts/qa-test-plan.sh QA-05 QA-06

# Skip TLS verification (self-signed certs)
./scripts/qa-test-plan.sh --insecure

# Custom cluster domains
export EAST_DOMAIN="cluster-64k4b.64k4b.sandbox5146.opentlc.com"
export WEST_DOMAIN="cluster-7rt9h.7rt9h.sandbox1900.opentlc.com"
./scripts/qa-test-plan.sh

# Skip oc-dependent tests (run from outside the hub)
SKIP_OC=1 ./scripts/qa-test-plan.sh
```

---

## Test cases

### QA-01 — GitOps Sync

| | |
|---|---|
| **Component** | Argo CD |
| **What it verifies** | All 7 Applications (dev/test/prod x east/west + observability) report `Synced` and `Healthy`. |
| **How** | `oc get applications -n openshift-gitops` on the hub. |
| **Pass criteria** | Every application is `Synced / Healthy`. |
| **Requires** | `oc` authenticated to hub. |

### QA-02 — Ambient Mesh

| | |
|---|---|
| **Component** | Istio service mesh |
| **What it verifies** | Application pods have 1 container (no `istio-proxy` sidecar injected). |
| **How** | `oc get pods` in each `nfl-wallet-*` namespace and checks container count. |
| **Pass criteria** | No pod has an `istio-proxy` sidecar container. |
| **Requires** | `oc` authenticated to hub. |

### QA-03 — Egress (ESPN)

| | |
|---|---|
| **Component** | ServiceEntry + HTTPRoute |
| **What it verifies** | The ESPN external API is reachable from the test environment through the Istio service mesh egress configuration. |
| **How** | Sends HTTP requests to the ESPN route on test-east (`/auth/nfl` and `/public/nfl`). |
| **Pass criteria** | HTTP 200 on the public path, or HTTP 401/403 on the auth path (confirms the route exists). |

### QA-04 — RHDH Portal

| | |
|---|---|
| **Component** | Red Hat Developer Hub |
| **What it verifies** | API catalog shows `nfl-wallet-api-customers` with OpenAPI spec and Kuadrant plugin. |
| **How** | Manual verification — the script prints instructions. |
| **Result** | Always `SKIP` (manual). |

### QA-05 — Rate Limiting

| | |
|---|---|
| **Component** | Kuadrant RateLimitPolicy |
| **What it verifies** | After exceeding the rate limit quota, the gateway returns HTTP 429. |
| **How** | Sends 505 sequential requests with a valid `X-Api-Key` to `api-customers` on test-east and counts 200 vs 429 responses. |
| **Pass criteria** | At least one 429 response (rate limit enforced), or all 200s (endpoint reachable, rate limit not configured). Fails only if no 200s are received. |

### QA-06 — AuthPolicy

| | |
|---|---|
| **Component** | Kuadrant AuthPolicy (Authorino) |
| **What it verifies** | Test and prod endpoints **reject** requests without an API key and **accept** requests with a valid key. |
| **How** | 1) Sends requests without `X-Api-Key` to test-east, test-west, and prod-east — expects 401/403. 2) Sends a request with a valid key to test-east — expects 200. |
| **Pass criteria** | 401/403 without key on all targets; 200 with key on at least one attempt (up to 5 retries). |

### QA-07 — Cross-Cluster

| | |
|---|---|
| **Component** | Multi-cluster deployment |
| **What it verifies** | Both east and west clusters serve independent workloads for all 3 APIs and the webapp. |
| **How** | Sends requests to `api-customers`, `api-bills`, and `api-raiders` on dev-east and dev-west (no auth). Also checks the webapp root `/` on both clusters. |
| **Pass criteria** | HTTP 200 on all 8 checks (3 APIs x 2 clusters + webapp x 2 clusters). |

### QA-08 — Observability

| | |
|---|---|
| **Component** | Grafana + Promxy |
| **What it verifies** | The observability stack is deployed and serving metrics from both clusters. |
| **How** | 1) Checks Grafana route on the hub (expects 200/302). 2) Checks Promxy route (expects 200/302). 3) Queries `istio_requests_total` via Promxy API. |
| **Pass criteria** | Grafana and Promxy reachable; Prometheus returns metric data. |

### QA-09 — Swagger UI

| | |
|---|---|
| **Component** | API documentation |
| **What it verifies** | Each microservice serves its Swagger UI at `/api-<service>/swagger`. |
| **How** | Sends requests to `/api-customers/swagger`, `/api-bills/swagger`, and `/api-raiders/swagger` on dev-east. |
| **Pass criteria** | HTTP 200 or 301 (redirect to Swagger UI page). |

### QA-10 — Load Test

| | |
|---|---|
| **Component** | Gateway under load |
| **What it verifies** | The gateway handles concurrent traffic and optionally enforces rate limiting under load. |
| **How** | Launches 10 parallel workers, each sending 20 requests with a valid API key to `api-customers` on test-east (200 total). |
| **Pass criteria** | At least 30% success rate. If 429 responses are received, rate limiting is active. |

---

## Environment variables

| Variable | Default | Description |
|----------|---------|-------------|
| `EAST_DOMAIN` | `cluster-64k4b.64k4b.sandbox5146.opentlc.com` | East cluster domain |
| `WEST_DOMAIN` | `cluster-7rt9h.7rt9h.sandbox1900.opentlc.com` | West cluster domain |
| `HUB_DOMAIN` | `cluster-72nh2.dynamic.redhatworkshops.io` | Hub cluster domain (observability routes) |
| `API_KEY_CUSTOMERS` | `nfl-wallet-customers-key` | API key for Customers service |
| `API_KEY_BILLS` | `nfl-wallet-bills-key` | API key for Bills service |
| `API_KEY_RAIDERS` | `nfl-wallet-raiders-key` | API key for Raiders service |
| `RATE_LIMIT_REQUESTS` | `505` | Number of requests for QA-05 |
| `RATE_LIMIT_EXPECTED` | `500` | Expected limit before 429 |
| `LOAD_WORKERS` | `10` | Concurrent workers for QA-10 |
| `LOAD_REQUESTS` | `20` | Requests per worker for QA-10 |
| `SKIP_OC` | `0` | Set to `1` to skip tests that require `oc` CLI |
| `SCHEME` | `https` | Protocol (`http` or `https`) |
| `ARGOCD_NS` | `openshift-gitops` | Argo CD namespace on the hub |

---

## Example output

```
═══════════════════════════════════════════════════════════
  Stadium Wallet — QA Test Plan
═══════════════════════════════════════════════════════════
  East: cluster-64k4b.64k4b.sandbox5146.opentlc.com
  West: cluster-7rt9h.7rt9h.sandbox1900.opentlc.com
  Hub:  cluster-72nh2.dynamic.redhatworkshops.io

  PASS  QA-01  All applications are Synced and Healthy
  PASS  QA-02  No istio-proxy sidecar injected
  PASS  QA-03  ESPN egress working via public path
  SKIP  QA-04  Manual verification required (RHDH UI)
  PASS  QA-05  Endpoint reachable (252 x 200)
  PASS  QA-06  AuthPolicy enforced — 401 without key, 200 with key
  PASS  QA-07  Both clusters (east + west) serve APIs and webapp
  PASS  QA-08  Observability stack reachable with metrics
  PASS  QA-09  Swagger UI accessible for all APIs
  PASS  QA-10  Load test: 110/200 succeeded (55%)

  PASS: 9  FAIL: 0  SKIP: 1  Total: 10
```

---

## Cluster endpoints tested

The script tests the following Route hostnames across environments:

| Environment | East | West |
|-------------|------|------|
| dev (no auth) | `nfl-wallet-dev.apps.<EAST_DOMAIN>` | `nfl-wallet-dev.apps.<WEST_DOMAIN>` |
| test (API key) | `nfl-wallet-test.apps.<EAST_DOMAIN>` | `nfl-wallet-test.apps.<WEST_DOMAIN>` |
| prod (API key) | `nfl-wallet-prod.apps.<EAST_DOMAIN>` | `nfl-wallet-prod.apps.<WEST_DOMAIN>` |
| ESPN (test only) | `nfl-wallet-test-espn.apps.<EAST_DOMAIN>` | — |
| Grafana (hub) | `grafana-nfl-wallet-service.apps.<HUB_DOMAIN>` | — |
| Promxy (hub) | `promxy-acm-observability.apps.<HUB_DOMAIN>` | — |
