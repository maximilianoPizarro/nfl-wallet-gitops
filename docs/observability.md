---
layout: default
title: Observability
---

# Observability

This page describes how to observe NFL Wallet traffic across **dev**, **test**, and **prod**: API test scripts, **Grafana** with the **Grafana Operator**, and visualization in **Kiali**.

---

## 1. Test script: run-tests.sh

The **`observability/run-tests.sh`** script runs `curl` against dev, test, and prod APIs to generate traffic visible in Kiali and Grafana.

The Route host in each environment follows the pattern **`nfl-wallet-<env>.apps.<cluster-domain>`** (e.g. prod: `nfl-wallet-prod.apps.cluster-thmg4.thmg4.sandbox4076.opentlc.com`).

### Option 1: CLUSTER_DOMAIN (recommended)

Set **`CLUSTER_DOMAIN`** to your OpenShift apps domain:

```bash
export CLUSTER_DOMAIN="cluster-thmg4.thmg4.sandbox4076.opentlc.com"
export API_KEY_TEST="nfl-wallet-customers-key"
export API_KEY_PROD="nfl-wallet-customers-key"
./observability/run-tests.sh all
```

### Option 2: East + West (ACM)

With ACM, set `EAST_DOMAIN` and `WEST_DOMAIN`:

```bash
export EAST_DOMAIN=cluster-thmg4.thmg4.sandbox4076.opentlc.com
export WEST_DOMAIN=cluster-2tjvj.2tjvj.sandbox5367.opentlc.com
export API_KEY_TEST=nfl-wallet-customers-key
export API_KEY_PROD=nfl-wallet-customers-key
./observability/run-tests.sh loop
```

### Script commands

| Command | Description |
|---------|-------------|
| `./observability/run-tests.sh all` | Runs dev, test, and prod. |
| `./observability/run-tests.sh dev` | Dev only (no API key). |
| `./observability/run-tests.sh test` | Test only (API_KEY_TEST). |
| `./observability/run-tests.sh prod` | Prod only (API_KEY_PROD). |
| `./observability/run-tests.sh canary` | Canary host only (API_KEY_PROD). |
| `./observability/run-tests.sh loop` | Loop: dev + test + prod. |

---

## 2. Grafana Operator and nfl-wallet-observability

The **`nfl-wallet-observability/`** directory contains the Kustomize configuration for Grafana, dashboard, and ServiceMonitors, based on `observability/` with patches for single-cluster.

### Contents

| Resource | Description |
|----------|-------------|
| `observability/` | Base: Grafana instance, datasource, dashboard |
| `nfl-wallet-observability/` | Patches: cluster domain, datasource URL, single-cluster dashboard |
| `servicemonitors-nfl-wallet/` | ServiceMonitors and PodMonitors for gateway and waypoint |

### Apply

```bash
kubectl kustomize nfl-wallet-observability | kubectl apply -f -
```

Or via Argo CD: create an Application pointing to `nfl-wallet-observability`.

### Namespace

By default it deploys to `openshift-cluster-observability-operator`. To use `observability`, edit `namespace` in `nfl-wallet-observability/kustomization.yaml`.

### Dashboard

The "NFL Wallet – All environments" dashboard includes:
- **Environment (namespace)** variable to filter by nfl-wallet-dev, nfl-wallet-test, nfl-wallet-prod.
- Panels: request rate, response codes, duration, error rate, rate by service.

---

## 3. Manual curl examples

### Dev (no authentication)

```bash
export GATEWAY_HOST="nfl-wallet-dev.apps.cluster-thmg4.thmg4.sandbox4076.opentlc.com"
curl -s -w "\nHTTP_CODE:%{http_code}\n" "https://${GATEWAY_HOST}/api-customers/Customers"
curl -s -w "\nHTTP_CODE:%{http_code}\n" "https://${GATEWAY_HOST}/api-bills/Bills"
```

### Test and prod (API key required)

```bash
export GATEWAY_HOST="nfl-wallet-test.apps.cluster-thmg4.thmg4.sandbox4076.opentlc.com"
curl -s -H "X-Api-Key: nfl-wallet-customers-key" "https://${GATEWAY_HOST}/api-customers/Customers"
```

---

## 4. Traffic in Kiali

- Traffic that goes through the **Istio gateway** into the mesh is visible in **Kiali** (service graph, traffic by namespace/workload, response codes, latency).
- Use the **Application** or **Namespace** view and select `nfl-wallet-dev`, `nfl-wallet-test`, or `nfl-wallet-prod`.
- Run the script or curl examples with the correct host, then refresh Kiali.

---

## 5. ServiceMonitors and Prometheus

The ServiceMonitors in `nfl-wallet-observability/servicemonitors-nfl-wallet/` select gateway and waypoint Services by label `gateway.networking.k8s.io/gateway-name`. Prometheus must discover them for Istio metrics to be available.

**Verify targets in Prometheus:** Status → Targets. `nfl-wallet-*-gateway-metrics` and `nfl-wallet-*-waypoint-metrics` should show as UP.

---

## 6. Troubleshooting

### HTTP 503 "Application is not available"

- **ACM:** Use the **managed cluster** domain (east/west), not the hub.
- Verify the Route exists: `oc get route -n nfl-wallet-prod`
- Verify backend pods are ready: `oc get pods -n nfl-wallet-prod`

### HTTP 401 on test/prod

- Verify API key Secrets exist in the namespace: `kubectl get secrets -n nfl-wallet-test -l api=nfl-wallet-test`
- Verify the Secret value matches the `X-Api-Key` header
- Verify AuthPolicy and Authorino

### No data in Grafana dashboard

1. Generate traffic with `./observability/run-tests.sh loop`
2. Verify Prometheus targets (Status → Targets)
3. Verify Service labels: `kubectl get svc -n nfl-wallet-prod -l gateway.networking.k8s.io/gateway-name`
4. In Grafana Explore, run `istio_requests_total` to confirm metrics exist
