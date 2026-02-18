# Observability

This folder contains documentation and assets for observing NFL Wallet traffic across **dev**, **test**, and **prod**: example API calls (curl) to generate traffic visible in **Kiali**, and a **Grafana** dashboard that aggregates metrics for all environments.

---

## 1. Example API calls (curl)

Use the following curl commands to hit the APIs through the gateway. Replace `GATEWAY_HOST` with your actual gateway host (or use the hostnames from your HTTPRoutes, e.g. `api-nfl-wallet-dev.local`, `api-nfl-wallet-test.local`, `api-nfl-wallet-prod.local`). If you use TLS, change `http://` to `https://`. Traffic sent through the gateway will appear in **Kiali** (service graph and traffic metrics) and in **Grafana** when the dashboard is configured.

If your HTTPRoutes use different paths (e.g. `/customers` instead of `/api/customers`), adjust the URLs in the examples accordingly.

### Dev (no authentication)

Dev does not require an API key. Use the dev hostname:

```bash
# Replace GATEWAY_HOST with your dev API host (e.g. api-nfl-wallet-dev.local or your ingress)
export GATEWAY_HOST="api-nfl-wallet-dev.local"

# Health or root (if supported)
curl -s -o /dev/null -w "%{http_code}" "http://${GATEWAY_HOST}/"

# Customers API
curl -s -w "\nHTTP_CODE:%{http_code}\n" "http://${GATEWAY_HOST}/api/customers"

# Bills API
curl -s -w "\nHTTP_CODE:%{http_code}\n" "http://${GATEWAY_HOST}/api/bills"

# Raiders API
curl -s -w "\nHTTP_CODE:%{http_code}\n" "http://${GATEWAY_HOST}/api/raiders"
```

### Test (API key required)

Test and prod require a valid API key in the `Authorization` header (or the header your gateway expects). Use the **test** hostname and a key that is valid for the test environment:

```bash
export GATEWAY_HOST="api-nfl-wallet-test.local"
export API_KEY="your-test-api-key"

curl -s -w "\nHTTP_CODE:%{http_code}\n" \
  -H "Authorization: Bearer ${API_KEY}" \
  "http://${GATEWAY_HOST}/api/customers"

curl -s -w "\nHTTP_CODE:%{http_code}\n" \
  -H "Authorization: Bearer ${API_KEY}" \
  "http://${GATEWAY_HOST}/api/bills"

curl -s -w "\nHTTP_CODE:%{http_code}\n" \
  -H "Authorization: Bearer ${API_KEY}" \
  "http://${GATEWAY_HOST}/api/raiders"
```

### Prod (API key required)

Use the **prod** hostname and a prod API key:

```bash
export GATEWAY_HOST="api-nfl-wallet-prod.local"
export API_KEY="your-prod-api-key"

curl -s -w "\nHTTP_CODE:%{http_code}\n" \
  -H "Authorization: Bearer ${API_KEY}" \
  "http://${GATEWAY_HOST}/api/customers"

curl -s -w "\nHTTP_CODE:%{http_code}\n" \
  -H "Authorization: Bearer ${API_KEY}" \
  "http://${GATEWAY_HOST}/api/bills"

curl -s -w "\nHTTP_CODE:%{http_code}\n" \
  -H "Authorization: Bearer ${API_KEY}" \
  "http://${GATEWAY_HOST}/api/raiders"
```

### Blue/Green hostname (prod + test weighted)

If you use the Blue/Green HTTPRoute with a single hostname (e.g. `api-nfl-wallet.local`), traffic will be split between prod and test. Use the same API key format as prod/test (depending on how the route is secured):

```bash
export GATEWAY_HOST="api-nfl-wallet.local"
export API_KEY="your-api-key"

curl -s -w "\nHTTP_CODE:%{http_code}\n" \
  -H "Authorization: Bearer ${API_KEY}" \
  "http://${GATEWAY_HOST}/api/customers"
```

### Looping to generate visible traffic (Kiali / metrics)

To see sustained traffic in Kiali and in the Grafana dashboard, run a short loop:

```bash
# Dev: 20 requests to each of the three APIs
for i in $(seq 1 20); do
  curl -s -o /dev/null "http://api-nfl-wallet-dev.local/api/customers"
  curl -s -o /dev/null "http://api-nfl-wallet-dev.local/api/bills"
  curl -s -o /dev/null "http://api-nfl-wallet-dev.local/api/raiders"
done
```

Adjust the hostname and add `-H "Authorization: Bearer $API_KEY"` for test or prod.

---

## 2. Viewing traffic in Kiali

- Traffic that goes through the **Istio gateway** and into the mesh is visible in **Kiali** (service graph, traffic by namespace/workload, response codes, and latency).
- Use the **Application** or **Namespace** view and select `nfl-wallet-dev`, `nfl-wallet-test`, or `nfl-wallet-prod` to see traffic per environment.
- Run the curl examples above (with the correct host so requests hit the gateway) and refresh Kiali to see the new requests.

---

## 3. Grafana dashboard (all environments)

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
