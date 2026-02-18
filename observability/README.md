# Observability

This folder contains documentation and assets for observing NFL Wallet traffic across **dev**, **test**, and **prod**: a **bash script** to run API tests, **Grafana Operator** YAMLs to visualize traffic in Grafana, and manual curl examples for Kiali.

---

## 1. Bash script: run tests

**`run-tests.sh`** runs curl against dev, test, and prod APIs (and can generate sustained traffic for Kiali/Grafana).

**URL pattern:** The gateway route host in each environment follows **`nfl-wallet-<env>.apps.<cluster-domain>`** (e.g. prod: `nfl-wallet-prod.apps.cluster-lzdjz.lzdjz.sandbox1796.opentlc.com`). The script uses this same pattern by default.

**API key (pruebas):** Default for test/prod is **`nfl-wallet-customers-key`** (same as in helm-values). The script uses it by default.

**Respuestas al abrir la URL en el navegador (esperado):**
- **Prod** (`https://nfl-wallet-prod.apps.../`): **401** — el gateway exige el header `X-Api-Key`; el navegador no lo envía.
- **Test** (`https://nfl-wallet-test.apps.../`): **404** — la ruta suele exponer solo `/api/*`, no la raíz `/`.

**Probar correctamente:** Usar el script o curl contra `/api/customers` (o `/api/bills`, `/api/raiders`) con el header `X-Api-Key`:

```bash
# Test
curl -s -w "\n%{http_code}\n" -H "X-Api-Key: nfl-wallet-customers-key" \
  "https://nfl-wallet-test.apps.cluster-lzdjz.lzdjz.sandbox1796.opentlc.com/api/customers"

# Prod
curl -s -w "\n%{http_code}\n" -H "X-Api-Key: nfl-wallet-customers-key" \
  "https://nfl-wallet-prod.apps.cluster-lzdjz.lzdjz.sandbox1796.opentlc.com/api/customers"
```

```bash
chmod +x observability/run-tests.sh
# Con valores por defecto (API key nfl-wallet-customers-key)
export CLUSTER_DOMAIN="cluster-lzdjz.lzdjz.sandbox1796.opentlc.com"
./observability/run-tests.sh all

# O definir hosts explícitos
export DEV_HOST="nfl-wallet-dev.apps.cluster-lzdjz.lzdjz.sandbox1796.opentlc.com"
export TEST_HOST="nfl-wallet-test.apps.cluster-lzdjz.lzdjz.sandbox1796.opentlc.com"
export PROD_HOST="nfl-wallet-prod.apps.cluster-lzdjz.lzdjz.sandbox1796.opentlc.com"
./observability/run-tests.sh all
```

**Defaults:** Script uses `nfl-wallet-{dev|test|prod}.apps.cluster-lzdjz...` with `https` and API key **`nfl-wallet-customers-key`** for test/prod. Override `CLUSTER_DOMAIN` or `WILDCARD_URL` as needed.

| Command | Description |
|--------|-------------|
| `./observability/run-tests.sh all` | dev + test + prod |
| `./observability/run-tests.sh dev` | dev only |
| `./observability/run-tests.sh test` | test only (default key: nfl-wallet-customers-key) |
| `./observability/run-tests.sh prod` | prod only (default key: nfl-wallet-customers-key) |
| `./observability/run-tests.sh loop` | 20 requests per API for Kiali/Grafana |

Env vars: `CLUSTER_DOMAIN`, `WILDCARD_URL`, `DEV_HOST`, `TEST_HOST`, `PROD_HOST`, `API_KEY_TEST`, `API_KEY_PROD`, `SCHEME` (default `https`), `API_PATH` (default `/api`), `LOOP_COUNT` (default `20`).

---

## 2. Grafana Operator (YAMLs)

The **`grafana-operator/`** directory contains everything needed to use the **Grafana Operator** and visualize traffic in Grafana:

| File | Description |
|------|-------------|
| `namespace.yaml` | Namespace `observability` (optional). |
| `grafana-instance.yaml` | **Grafana** CR – deploys a Grafana instance (skip if you already have one). |
| `grafana-datasource-prometheus.yaml` | **GrafanaDatasource** – Prometheus for Istio metrics. **Edit the `url`** to your Prometheus (e.g. `http://prometheus-operated.monitoring.svc.cluster.local:9090`). |
| `grafana-dashboard-configmap.yaml` | **ConfigMap** with the NFL Wallet “All environments” dashboard JSON. |
| `grafana-dashboard-nfl-wallet.yaml` | **GrafanaDashboard** CR – provisions the dashboard into Grafana. |

**Apply (after editing the Prometheus URL in the datasource):**

```bash
kubectl apply -f observability/grafana-operator/namespace.yaml
kubectl apply -f observability/grafana-operator/grafana-instance.yaml
kubectl apply -f observability/grafana-operator/grafana-datasource-prometheus.yaml
kubectl apply -f observability/grafana-operator/grafana-dashboard-configmap.yaml
kubectl apply -f observability/grafana-operator/grafana-dashboard-nfl-wallet.yaml
```

See **`grafana-operator/README.md`** for namespace/selector customization and OpenShift Route.

---

## 3. Example API calls (curl, manual)

Use the following curl commands to hit the APIs through the gateway. The gateway route host follows **`nfl-wallet-<env>.apps.<cluster-domain>`** (e.g. `nfl-wallet-prod.apps.cluster-lzdjz.lzdjz.sandbox1796.opentlc.com`). Use `https://` for these hosts. Traffic sent through the gateway will appear in **Kiali** (service graph and traffic metrics) and in **Grafana** when the dashboard is configured.

If your HTTPRoutes use different paths (e.g. `/customers` instead of `/api/customers`), adjust the URLs in the examples accordingly.

### Dev (no authentication)

Dev does not require an API key. Use the dev hostname:

```bash
# Dev: same host pattern as gateway route (nfl-wallet-<env>.apps.<cluster-domain>)
export GATEWAY_HOST="nfl-wallet-dev.apps.cluster-lzdjz.lzdjz.sandbox1796.opentlc.com"

# Health or root (if supported)
curl -s -o /dev/null -w "%{http_code}" "https://${GATEWAY_HOST}/"

# Customers API
curl -s -w "\nHTTP_CODE:%{http_code}\n" "https://${GATEWAY_HOST}/api/customers"

# Bills API
curl -s -w "\nHTTP_CODE:%{http_code}\n" "https://${GATEWAY_HOST}/api/bills"

# Raiders API
curl -s -w "\nHTTP_CODE:%{http_code}\n" "https://${GATEWAY_HOST}/api/raiders"
```

### Test (API key required)

Test and prod require el header **`X-Api-Key`** con el valor configurado en el Helm chart (`nfl-wallet.apiKeys.customers`, `.bills`, o `.raiders`):

```bash
export GATEWAY_HOST="nfl-wallet-test.apps.cluster-lzdjz.lzdjz.sandbox1796.opentlc.com"
export API_KEY="nfl-wallet-customers-key"

curl -s -w "\nHTTP_CODE:%{http_code}\n" \
  -H "X-Api-Key: ${API_KEY}" \
  "https://${GATEWAY_HOST}/api/customers"

curl -s -w "\nHTTP_CODE:%{http_code}\n" \
  -H "X-Api-Key: ${API_KEY}" \
  "https://${GATEWAY_HOST}/api/bills"

curl -s -w "\nHTTP_CODE:%{http_code}\n" \
  -H "X-Api-Key: ${API_KEY}" \
  "https://${GATEWAY_HOST}/api/raiders"
```

### Prod (API key required)

Use the **prod** hostname and the same API key as in the Helm chart (`nfl-wallet.apiKeys.*` in `nfl-wallet-prod/helm-values.yaml`):

```bash
export GATEWAY_HOST="nfl-wallet-prod.apps.cluster-lzdjz.lzdjz.sandbox1796.opentlc.com"
export API_KEY="<value from nfl-wallet-prod apiKeys.customers | bills | raiders>"

curl -s -w "\nHTTP_CODE:%{http_code}\n" \
  -H "X-Api-Key: ${API_KEY}" \
  "https://${GATEWAY_HOST}/api/customers"

curl -s -w "\nHTTP_CODE:%{http_code}\n" \
  -H "X-Api-Key: ${API_KEY}" \
  "https://${GATEWAY_HOST}/api/bills"

curl -s -w "\nHTTP_CODE:%{http_code}\n" \
  -H "X-Api-Key: ${API_KEY}" \
  "https://${GATEWAY_HOST}/api/raiders"
```

### Blue/Green hostname (prod + test weighted)

If you use the Blue/Green HTTPRoute with a single hostname, use that host and the same API key as in the Helm chart for the environment the route targets:

```bash
export GATEWAY_HOST="nfl-wallet.apps.cluster-lzdjz.lzdjz.sandbox1796.opentlc.com"   # or your Blue/Green host
export API_KEY="<value from nfl-wallet apiKeys (prod or test)>"

curl -s -w "\nHTTP_CODE:%{http_code}\n" \
  -H "X-Api-Key: ${API_KEY}" \
  "https://${GATEWAY_HOST}/api/customers"
```

### Looping to generate visible traffic (Kiali / metrics)

To see sustained traffic in Kiali and in the Grafana dashboard, run a short loop:

```bash
# Dev: 20 requests to each of the three APIs (use your cluster domain)
for i in $(seq 1 20); do
  curl -s -o /dev/null "https://nfl-wallet-dev.apps.cluster-lzdjz.lzdjz.sandbox1796.opentlc.com/api/customers"
  curl -s -o /dev/null "https://nfl-wallet-dev.apps.cluster-lzdjz.lzdjz.sandbox1796.opentlc.com/api/bills"
  curl -s -o /dev/null "https://nfl-wallet-dev.apps.cluster-lzdjz.lzdjz.sandbox1796.opentlc.com/api/raiders"
done
```

For test or prod, use the hostname for that env and set `API_KEY`; then add `-H "X-Api-Key: $API_KEY"`.

---

## 4. Viewing traffic in Kiali

- Traffic that goes through the **Istio gateway** and into the mesh is visible in **Kiali** (service graph, traffic by namespace/workload, response codes, and latency).
- Use the **Application** or **Namespace** view and select `nfl-wallet-dev`, `nfl-wallet-test`, or `nfl-wallet-prod` to see traffic per environment.
- Run the curl examples above (with the correct host so requests hit the gateway) and refresh Kiali to see the new requests.

---

## 5. Grafana dashboard JSON (manual import)

The file **`grafana-dashboard-nfl-wallet-environments.json`** defines a Grafana dashboard that shows metrics for **all three environments** (dev, test, prod) in one place.

### What it contains

- **Environment selector**: Variable to filter by namespace (`nfl-wallet-dev`, `nfl-wallet-test`, `nfl-wallet-prod`) or view all.
- **Request rate**: Request rate per environment (from Istio/Prometheus metrics).
- **Response codes**: Success vs error ratio by environment.
- **Latency**: Request duration by environment (e.g. p50, p99).

### How to import

1. In Grafana, go to **Dashboards** → **Import**.
2. Upload **`grafana-dashboard-nfl-wallet-environments.json`** or paste its contents.
3. Select the **Prometheus** datasource that scrapes your mesh (e.g. Istio metrics).
4. Save the dashboard.

Ensure Prometheus is scraping the Istio/Envoy metrics (e.g. from the gateway and sidecars or ztunnel). The dashboard uses metrics such as `istio_requests_total` and Istio request duration; if your metric names differ, adjust the panel queries in the JSON.
