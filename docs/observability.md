# Observability

This page describes how to observe NFL Wallet traffic across **dev**, **test**, and **prod**: run API tests via a **bash script** (including wildcard URL), provision **Grafana** with the **Grafana Operator** YAMLs, and view traffic in **Kiali**. All content is in English.

---

## 1. Bash script: run API tests

The script **`observability/run-tests.sh`** runs `curl` against dev, test, and prod APIs so that traffic appears in Kiali and Grafana.

The gateway route host in each environment uses the pattern **`nfl-wallet-<env>.apps.<cluster-domain>`** (e.g. prod: `nfl-wallet-prod.apps.cluster-lzdjz.lzdjz.sandbox1796.opentlc.com`). The script uses this same pattern by default.

### Option 1: CLUSTER_DOMAIN (recommended)

Set **`CLUSTER_DOMAIN`** to your OpenShift apps domain; the script builds `https://nfl-wallet-ENV.apps.<cluster-domain>`:

```bash
export CLUSTER_DOMAIN="cluster-lzdjz.lzdjz.sandbox1796.opentlc.com"
export API_KEY_TEST="<value from nfl-wallet-test apiKeys>"
export API_KEY_PROD="<value from nfl-wallet-prod apiKeys>"
./observability/run-tests.sh all
```

### Option 2: WILDCARD_URL

Set **`WILDCARD_URL`** with placeholder **`ENV`** (replaced by `dev`, `test`, or `prod`):

```bash
export WILDCARD_URL="https://nfl-wallet-ENV.apps.cluster-lzdjz.lzdjz.sandbox1796.opentlc.com"
export API_KEY_TEST="<value from nfl-wallet-test apiKeys.customers | bills | raiders>"
export API_KEY_PROD="<value from nfl-wallet-prod apiKeys.customers | bills | raiders>"
./observability/run-tests.sh all
```

### Option 3: Explicit hosts

Set each host and scheme explicitly (same pattern as the gateway route):

```bash
export DEV_HOST="nfl-wallet-dev.apps.cluster-lzdjz.lzdjz.sandbox1796.opentlc.com"
export TEST_HOST="nfl-wallet-test.apps.cluster-lzdjz.lzdjz.sandbox1796.opentlc.com"
export PROD_HOST="nfl-wallet-prod.apps.cluster-lzdjz.lzdjz.sandbox1796.opentlc.com"
export SCHEME="https"
export API_KEY_TEST="<value from nfl-wallet-test apiKeys>"
export API_KEY_PROD="<value from nfl-wallet-prod apiKeys>"
./observability/run-tests.sh all
```

**Defaults:** With no env vars set, the script uses `nfl-wallet-{dev|test|prod}.apps.cluster-lzdjz.lzdjz.sandbox1796.opentlc.com` and `SCHEME=https`. Override `CLUSTER_DOMAIN` or `WILDCARD_URL` to match your cluster.

**API keys:** Use the same values as in the Helm chart (`nfl-wallet.apiKeys.customers`, `.bills`, or `.raiders` in the corresponding env’s `helm-values.yaml` or the Secret that backs them).

### Script usage

| Command | Description |
|--------|-------------|
| `./observability/run-tests.sh all` | Run dev, test, and prod (default). |
| `./observability/run-tests.sh dev` | Dev only (no API key). |
| `./observability/run-tests.sh test` | Test only (requires `API_KEY_TEST`). |
| `./observability/run-tests.sh prod` | Prod only (requires `API_KEY_PROD`). |
| `./observability/run-tests.sh loop` | Send 20 requests per API to generate sustained traffic for Kiali/Grafana. |

**Environment variables:** `CLUSTER_DOMAIN`, `WILDCARD_URL`, `DEV_HOST`, `TEST_HOST`, `PROD_HOST`, `API_KEY_TEST`, `API_KEY_PROD`, `SCHEME` (default `https`), `API_PATH` (default `/api`), `LOOP_COUNT` (default `20`).

---

## 2. Grafana Operator (YAMLs)

The **`observability/grafana-operator/`** directory contains YAML manifests to use with the [Grafana Operator](https://grafana.github.io/grafana-operator/) so you can visualize NFL Wallet traffic in Grafana without manual import.

### Contents

| File | Description |
|------|-------------|
| `namespace.yaml` | Namespace `observability` (optional; you can use your own Grafana namespace). |
| `grafana-instance.yaml` | **Grafana** CR – deploys a Grafana instance with label `dashboards: nfl-wallet`. Omit if you already have Grafana; then add this label or adjust `instanceSelector` in the datasource and dashboard. |
| `grafana-datasource-prometheus.yaml` | **GrafanaDatasource** – Prometheus for Istio/mesh metrics. **Edit `spec.datasource.url`** to your Prometheus URL (e.g. `http://prometheus-operated.monitoring.svc.cluster.local:9090`). |
| `grafana-dashboard-configmap.yaml` | **ConfigMap** – JSON for the “NFL Wallet – All environments” dashboard. |
| `grafana-dashboard-nfl-wallet.yaml` | **GrafanaDashboard** CR – provisions the dashboard into Grafana. |

### Apply order

1. Create the namespace (or use an existing one):  
   `kubectl apply -f observability/grafana-operator/namespace.yaml`
2. (Optional) Deploy the Grafana instance:  
   `kubectl apply -f observability/grafana-operator/grafana-instance.yaml`
3. Edit the Prometheus URL in `grafana-datasource-prometheus.yaml`, then:  
   `kubectl apply -f observability/grafana-operator/grafana-datasource-prometheus.yaml`
4. Apply the dashboard ConfigMap and CR:  
   `kubectl apply -f observability/grafana-operator/grafana-dashboard-configmap.yaml`  
   `kubectl apply -f observability/grafana-operator/grafana-dashboard-nfl-wallet.yaml`

Or apply the whole directory after editing the Prometheus URL:  
`kubectl apply -f observability/grafana-operator/`

### Dashboard panels

The provisioned dashboard includes:

- **Environment (namespace)** variable to filter by `nfl-wallet-dev`, `nfl-wallet-test`, `nfl-wallet-prod`, or view all.
- Request rate by environment.
- Response codes (2xx, 4xx, 5xx) by environment.
- Request duration (p50, p99) by environment.
- Total requests (last 1h) and error rate by environment.
- Request rate by environment and service.

Prometheus must scrape Istio/Envoy metrics (e.g. from the gateway). The dashboard uses `istio_requests_total` and `istio_request_duration_milliseconds_bucket`.

---

## 3. Manual curl examples

If you prefer to run curl by hand, use the gateway host pattern **`nfl-wallet-<env>.apps.<cluster-domain>`** (e.g. `nfl-wallet-prod.apps.cluster-lzdjz.lzdjz.sandbox1796.opentlc.com`) with `https://`.

### Dev (no authentication)

```bash
export GATEWAY_HOST="nfl-wallet-dev.apps.cluster-lzdjz.lzdjz.sandbox1796.opentlc.com"
curl -s -w "\nHTTP_CODE:%{http_code}\n" "https://${GATEWAY_HOST}/api/customers"
curl -s -w "\nHTTP_CODE:%{http_code}\n" "https://${GATEWAY_HOST}/api/bills"
curl -s -w "\nHTTP_CODE:%{http_code}\n" "https://${GATEWAY_HOST}/api/raiders"
```

### Test and prod (API key required)

Use the same API key as in the Helm chart (`nfl-wallet.apiKeys.customers`, `.bills`, or `.raiders` in the corresponding env’s `helm-values.yaml` or the Secret that backs them).

```bash
export GATEWAY_HOST="nfl-wallet-test.apps.cluster-lzdjz.lzdjz.sandbox1796.opentlc.com"
export API_KEY="<value from nfl-wallet-test apiKeys.customers | bills | raiders>"
curl -s -w "\nHTTP_CODE:%{http_code}\n" -H "Authorization: Bearer ${API_KEY}" "https://${GATEWAY_HOST}/api/customers"
# Same for bills and raiders; for prod use nfl-wallet-prod.apps.<cluster-domain> and prod apiKeys value.
```

If your HTTPRoutes use different paths (e.g. `/customers` instead of `/api/customers`), set `API_PATH` in the script or adjust the URLs above.

---

## 4. Viewing traffic in Kiali

- Traffic that goes through the **Istio gateway** into the mesh is visible in **Kiali** (service graph, traffic by namespace/workload, response codes, latency).
- Use the **Application** or **Namespace** view and select `nfl-wallet-dev`, `nfl-wallet-test`, or `nfl-wallet-prod`.
- Run the bash script or curl examples with the correct host so requests hit the gateway, then refresh Kiali to see the new traffic.

---

## 5. Grafana dashboard JSON (manual import)

If you do not use the Grafana Operator, you can import the dashboard manually:

1. Open **`observability/grafana-dashboard-nfl-wallet-environments.json`** in the repository.
2. In Grafana, go to **Dashboards** → **Import**, then upload the file or paste its contents.
3. Select the **Prometheus** datasource that scrapes your mesh and save the dashboard.

The dashboard shows the same panels as described in section 2 (request rate, response codes, latency, error rate, etc.) with an **Environment (namespace)** variable.

---

## Quick reference

| Resource | Location in repo |
|----------|------------------|
| Bash test script | `observability/run-tests.sh` |
| Grafana Operator YAMLs | `observability/grafana-operator/` |
| Grafana Operator README | `observability/grafana-operator/README.md` |
| Dashboard JSON (manual import) | `observability/grafana-dashboard-nfl-wallet-environments.json` |

All explanations above are in English and are intended for the GitHub Pages documentation site.
