---
layout: default
title: Observability
---

# Observability

This page describes how to observe NFL Wallet traffic across **dev**, **test**, and **prod**: run API tests via a **bash script** (including wildcard URL), provision **Grafana** with the **Grafana Operator** YAMLs, and view traffic in **Kiali**. 

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

**Defaults:** With no env vars set, the script uses `nfl-wallet-{dev|test|prod}.apps.cluster-lzdjz...`, `SCHEME=https`, and API key **`nfl-wallet-customers-key`** for test/prod (same as helm-values default for testing).

### Option 4: East + West (loop en ambos clusters, listo para copiar/pegar)

Con ACM sueles tener east y west. Para generar tráfico en **ambos** clusters (misma lógica que `scripts/test-apis.sh`), define `EAST_DOMAIN` y `WEST_DOMAIN` y ejecuta el loop:

```bash
export EAST_DOMAIN=cluster-h625z.h625z.sandbox613.opentlc.com
export WEST_DOMAIN=cluster-2l9nd.dynamic.redhatworkshops.io
export API_KEY_TEST=nfl-wallet-customers-key
export API_KEY_PROD=nfl-wallet-customers-key
./observability/run-tests.sh loop
```

Sustituye los dominios por los de tu `app-nfl-wallet-acm.yaml` (east/west). El loop hará requests a dev, test y prod en ambos clusters y mostrará cada request como `code GET url`.

**When opening the URL in a browser:** **Prod** returns **401** (auth required; browser does not send the API key). **Test** may return **404** on `/` because the route typically exposes only `/api/*`, not the root. To verify: use the script or call `/api/customers` with the header: `curl -H "X-Api-Key: nfl-wallet-customers-key" "https://nfl-wallet-prod.apps..../api/customers"`.

### Script usage

| Comando | Descripción |
|--------|-------------|
| `./observability/run-tests.sh all` | Ejecuta dev, test y prod (por defecto). |
| `./observability/run-tests.sh dev` | Solo dev (sin API key). |
| `./observability/run-tests.sh test` | Solo test (API_KEY_TEST). |
| `./observability/run-tests.sh prod` | Solo prod (API_KEY_PROD). |
| `./observability/run-tests.sh canary` | Solo host canary blue/green (API_KEY_PROD). |
| `./observability/run-tests.sh loop` | Loop: dev + test + prod (20 requests por API). |
| `./observability/run-tests.sh loop dev` | Loop solo dev. |
| `./observability/run-tests.sh loop test` | Loop solo test (requiere API_KEY_TEST). |
| `./observability/run-tests.sh loop prod` | Loop solo prod (requiere API_KEY_PROD). |
| `./observability/run-tests.sh loop canary` | Loop solo canary (requiere API_KEY_PROD). |

### Variables de entorno (opciones)

| Variable | Uso por defecto / descripción |
|----------|-------------------------------|
| `CLUSTER_DOMAIN` | Construye `nfl-wallet-ENV.apps.<clusterDomain>`. Un solo cluster. |
| `EAST_DOMAIN` | Dominio del cluster east. Con `WEST_DOMAIN`, el loop llama a east y west. |
| `WEST_DOMAIN` | Dominio del cluster west. Con `EAST_DOMAIN`, el loop llama a east y west. |
| `DEV_HOST`, `TEST_HOST`, `PROD_HOST`, `CANARY_HOST` | Hosts explícitos (sustituyen el patrón por cluster). |
| `API_KEY_TEST`, `API_KEY_PROD` | API key para test y prod (por path: customers/bills/raiders). |
| `API_KEY_CUSTOMERS`, `API_KEY_BILLS`, `API_KEY_RAIDERS` | Keys por path para test (fallback: `API_KEY_TEST`). |
| `API_KEY_CUSTOMERS_PROD`, `API_KEY_BILLS_PROD`, `API_KEY_RAIDERS_PROD` | Keys por path para prod/canary (fallback: `API_KEY_PROD`). |
| `SCHEME` | `https` por defecto. |
| `API_PATH` | `/api` por defecto. |
| `LOOP_COUNT` | Número de iteraciones por API en loop (por defecto `20`). |

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

### How to set up the Grafana dashboard (step by step)

With apps deployed on **east** and **west**, you can run one Grafana per cluster (east and west) or a central Grafana that queries a Thanos aggregating both. Typical steps for **one cluster** (e.g. east):

1. **Install Grafana Operator** on the cluster where you want Grafana (east, west, or hub). On OpenShift, install the [Grafana Operator](https://grafana.github.io/grafana-operator/) from OperatorHub.

2. **Namespace and Grafana instance** (from the repo root):
   ```bash
   kubectl apply -f observability/grafana-operator/namespace.yaml
   kubectl apply -f observability/grafana-operator/grafana-instance.yaml
   ```
   If you already have a Grafana instance, skip `grafana-instance.yaml` and ensure it has the label `dashboards: nfl-wallet` (or change `instanceSelector` in the datasource and dashboard CRs).

3. **Prometheus/Thanos URL:** The dashboard uses Istio metrics (`istio_requests_total`, etc.). The datasource must be a Prometheus (or Thanos) that **scrapes the service mesh on that cluster** (gateway and pods in `nfl-wallet-dev`, `nfl-wallet-test`, `nfl-wallet-prod`).
   - Find the service:
     ```bash
     kubectl get svc -A | grep -E 'prometheus|thanos'
     ```
   - Common in-cluster URLs (**inside the cluster** only, not the `.apps.` route):
     - Prometheus User Workload (OpenShift):  
       `http://prometheus-user-workload.openshift-user-workload-monitoring.svc.cluster.local:9091`
     - Thanos Querier (OpenShift Cluster Observability):  
       `http://thanos-querier.openshift-monitoring.svc.cluster.local:9091`  
       (or your observability Thanos, e.g. `...openshift-cluster-observability-operator.svc.cluster.local:10902`)
   - Edit `observability/grafana-operator/grafana-datasource-prometheus.yaml` and set that URL in `spec.datasource.url`.

4. **Datasource and dashboard:**
   ```bash
   kubectl apply -f observability/grafana-operator/grafana-datasource-prometheus.yaml
   kubectl apply -f observability/grafana-operator/grafana-dashboard-configmap.yaml
   kubectl apply -f observability/grafana-operator/grafana-dashboard-nfl-wallet.yaml
   ```

5. **Access Grafana:** With `route.enabled: true` on the instance, the operator creates a Route. Get the URL:
   ```bash
   oc get route -n observability
   ```
   Use username **admin**; password is in the Secret:
   ```bash
   kubectl get secret -n observability -l app.kubernetes.io/name=grafana -o name
   kubectl get secret <secret-name> -n observability -o jsonpath='{.data.admin-password}' | base64 -d
   ```
   In the UI: **Dashboards** → **NFL Wallet – All environments**. Filter by **Environment (namespace)** (nfl-wallet-dev, nfl-wallet-test, nfl-wallet-prod).

6. **Ensure there is data:** Prometheus must be scraping the Istio gateway (PodMonitors in this repo in each nfl-wallet-* namespace). Generate traffic with `./scripts/test-apis.sh` or `./observability/run-tests.sh all` and refresh the dashboard; the time range must include that period.

**East and West separately:** To see metrics from **east** and **west** in one place, the datasource must point to a Thanos (or Prometheus) that aggregates both clusters (e.g. OpenShift Cluster Observability with multi-cluster collection). In that case set the datasource URL to that Thanos; if metrics have a cluster label, you can add a "Cluster" variable to the dashboard later.

### Dashboard panels

The provisioned dashboard includes:

- **Environment (namespace)** variable to filter by `nfl-wallet-dev`, `nfl-wallet-test`, `nfl-wallet-prod`, or view all.
- **Cluster (east/west)** variable when the datasource is Promxy/ACM Observability: filters by managed cluster so you can distinguish east vs west. The variable uses the `cluster` label that ACM Observability adds to metrics from each managed cluster. If the variable is empty, your metrics may not have that label (single-cluster or different aggregator).
- Request rate, response codes, duration, total requests, error rate, and rate by service — all by environment and (when available) by cluster.

Prometheus must scrape Istio/Envoy metrics (e.g. from the gateway). The dashboard uses `istio_requests_total` and `istio_request_duration_milliseconds_bucket`.

### Solo se ve tráfico dev en Grafana (test/prod/canary no aparecen)

Si en Grafana solo ves solicitudes a **dev** y no a test/prod/canary:

1. **Generar tráfico a test/prod/canary** — Las métricas solo aparecen si hay requests. Ejecuta el script contra esos entornos (y contra el cluster correcto):
   ```bash
   CLUSTER_DOMAIN=cluster-<east-or-west>.example.com API_KEY_PROD=nfl-wallet-customers-key ./observability/run-tests.sh test
   ./observability/run-tests.sh prod
   ./observability/run-tests.sh canary
   # o en bucle: ./observability/run-tests.sh loop prod
   ```
2. **No hace falta reiniciar Prometheus** — Reiniciar Prometheus no suele ser necesario. Lo importante es que el sistema de observabilidad (p. ej. ACM Observability que alimenta [Promxy](https://promxy-acm-observability.apps.cluster-g62mw.dynamic.redhatworkshops.io)) esté scrapeando los namespaces `nfl-wallet-dev`, `nfl-wallet-test` y `nfl-wallet-prod` en cada managed cluster (east y west). Los PodMonitors de este repo (en cada app) exponen el gateway; el Prometheus de cada cluster debe descubrirlos. Si solo dev tiene datos, comprueba en cada cluster que los PodMonitors de test/prod existen y que hay targets en Prometheus para esos namespaces.
3. **Datasource Promxy** — Si Grafana usa como datasource la URL de Promxy/ACM Observability (p. ej. `https://promxy-acm-observability.apps.cluster-g62mw.dynamic.redhatworkshops.io`), está recibiendo el tráfico agregado de todos los clusters. Usa la variable **Cluster (east/west)** del dashboard para filtrar por managed cluster. La label `cluster` en las métricas identifica el origen (east, west, etc.).

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
curl -s -w "\nHTTP_CODE:%{http_code}\n" -H "X-Api-Key: ${API_KEY}" "https://${GATEWAY_HOST}/api/customers"
# Same for bills and raiders; for prod use nfl-wallet-prod.apps.<cluster-domain> and prod apiKeys value.
```

If your HTTPRoutes use different paths (e.g. `/customers` instead of `/api/customers`), set `API_PATH` in the script or adjust the URLs above.

---

## 4. Viewing traffic in Kiali

- Traffic that goes through the **Istio gateway** into the mesh is visible in **Kiali** (service graph, traffic by namespace/workload, response codes, latency).
- Use the **Application** or **Namespace** view and select `nfl-wallet-dev`, `nfl-wallet-test`, or `nfl-wallet-prod`.
- Run the bash script or curl examples with the correct host so requests hit the gateway, then refresh Kiali to see the new traffic.

### Service mesh screenshots

![Kiali – service graph](service-mesh-kiali.png)

*Figure: Kiali service graph — traffic through the Istio gateway (nfl-wallet-dev/test/prod).*

![Kiali – traffic graph / topology](service-mesh-kiali-topology.png)

*Figure: Kiali Traffic Graph — topology of webapp, gateway, and APIs (customers, bills, raiders) across nfl-wallet-dev, nfl-wallet-test, and nfl-wallet-prod.*

![Grafana – mesh metrics](service-mesh-grafana.png)

*Figure: Grafana dashboard — request rate, response codes, and latency by environment (Istio metrics).*

![Grafana – NFL Wallet dashboard](grafana-dashboard.png)

*Figure: Grafana “NFL Wallet – All environments” dashboard with Environment variable (dev, test, prod).*

![Jaeger – distributed traces](jaegger-traces.png)

*Figure: Jaeger UI — distributed traces for requests through the Istio gateway (e.g. nfl-wallet-gateway-istio).*

### 4.0 Kiali config warning KIA1317 (Authorization Policies but no Waypoint)

Kiali may show: **KIA1317 – This workload has Authorization Policies but no Waypoint** for `nfl-wallet-gateway-istio` (and other gateways in dev/test/prod). That happens because Kuadrant AuthPolicies result in Istio `AuthorizationPolicy` resources targeting the gateway; Kiali then expects a **Waypoint** proxy when it sees L7 authorization policies (e.g. in ambient or when it assumes L7 enforcement).

**When you can ignore it**

- **Sidecar mode:** If the gateway pods have **Istio sidecar injection** (e.g. namespace label `istio-injection: enabled`), the sidecar enforces the AuthorizationPolicy. The policy is applied; KIA1317 is a warning only and can be ignored.
- Check sidecar: `kubectl get pod -n nfl-wallet-prod -l app=nfl-wallet-gateway-istio -o jsonpath='{.items[0].spec.containers[*].name}'` — you should see `istio-proxy` (or similar) in addition to the main container.

**To clear the warning (optional)**

If you use **Istio ambient mode** or want the warning gone:

1. **Install istioctl** (only if you want waypoints; not needed to fix KIA1317 in sidecar mode). If the default download fails, try a specific version or GitHub release:
   ```bash
   # Option A: Specific version (e.g. 1.24)
   curl -L https://istio.io/downloadIstio | ISTIO_VERSION=1.24.3 TARGET_ARCH=x86_64 sh -
   cd istio-1.24.3 && export PATH="$PWD/bin:$PATH"

   # Option B: Direct from GitHub (adjust version and os: linux-amd64, osx-arm64, etc.)
   # https://github.com/istio/istio/releases — download istio-<ver>-<os>-<arch>.tar.gz and extract bin/istioctl
   ```
   On **OpenShift**, use the CLI from the Red Hat OpenShift Service Mesh / Istio operator if available; waypoint support depends on your mesh version.

2. **Waypoint per namespace** (one waypoint for all workloads in that namespace). Use the **managed cluster** context (where the namespaces exist), not the hub:
   ```bash
   istioctl waypoint apply -n nfl-wallet-dev --wait
   istioctl waypoint apply -n nfl-wallet-test --wait
   istioctl waypoint apply -n nfl-wallet-prod --wait
   ```
   Requires Gateway API CRDs and Istio ambient/waypoint support. After the waypoint is ready, Kiali may stop reporting KIA1317 for that namespace.

3. **Namespace labels (ambient):** If using ambient, add the labels on each cluster where the namespaces exist:
   ```bash
   kubectl label namespace nfl-wallet-dev   istio.io/dataplane-mode=ambient istio.io/use-waypoint=waypoint --overwrite
   kubectl label namespace nfl-wallet-test istio.io/dataplane-mode=ambient istio.io/use-waypoint=waypoint --overwrite
   kubectl label namespace nfl-wallet-prod istio.io/dataplane-mode=ambient istio.io/use-waypoint=waypoint --overwrite
   ```

4. **Ensure namespaces are in the mesh:** If using sidecar only, ensure injection is enabled (see [§6.3 Istio sidecar](observability.md#63-fixing-istio-sidecar-container-not-found-in-pods) in this doc).

If you do not use ambient and the gateway has a sidecar, you can leave the config as-is and treat KIA1317 as an informational warning; no need to install istioctl or add waypoints.

---

## 4.1 Making traffic visible in the service mesh (Kiali and Grafana)

For traffic to appear in **Kiali** and in the **Grafana** dashboard (metrics like `istio_requests_total`), three things must be true:

1. **Traffic goes through the gateway**  
   Send requests to the gateway host (e.g. `https://nfl-wallet-dev.apps.<cluster-domain>/api/customers`), not directly to a Service URL inside the cluster. Use **`observability/run-tests.sh`** or the curl examples in this doc; they already target the gateway.

2. **Workloads are in the mesh**  
   The namespaces `nfl-wallet-dev`, `nfl-wallet-test`, and `nfl-wallet-prod` must be part of the Istio mesh (sidecar injection or ambient). The Gateway and HTTPRoutes are created by the Helm chart; ensure the mesh is installed and those namespaces are configured for injection if required.

3. **Prometheus scrapes Istio/Envoy metrics**  
   The Prometheus that Grafana uses (or that feeds your Thanos) must scrape the Istio proxy metrics from the gateway (and optionally from the API pods).  
   - **This repo includes a PodMonitor per environment:** `nfl-wallet-dev/templates/podmonitor-istio-gateway.yaml`, `nfl-wallet-test/templates/podmonitor-istio-gateway.yaml`, `nfl-wallet-prod/templates/podmonitor-istio-gateway.yaml`. They select pods with label `app: nfl-wallet-gateway-istio` and scrape port `status-port` (15020), path `/stats/prometheus`. When you deploy or sync each app (dev, test, prod), the PodMonitor is created in that namespace.  
   - **Prometheus must discover these PodMonitors:** The Prometheus instance that feeds your Grafana datasource (e.g. OpenShift User Workload Monitoring, or the Prometheus that backs the Thanos querier in `openshift-cluster-observability-operator`) must be configured to discover PodMonitors in `nfl-wallet-dev`, `nfl-wallet-test`, and `nfl-wallet-prod`. If it only watches specific namespaces, add these three.  
   - **If no targets appear:** Check gateway pod labels — run `kubectl get pods -n nfl-wallet-dev -l app=nfl-wallet-gateway-istio` (and test/prod). If no pods match, the nfl-wallet chart may use a different label; adjust `spec.selector.matchLabels` in the PodMonitor template to match. Also verify the port name on the istio-proxy container (`kubectl get pod -n <ns> <gateway-pod> -o jsonpath='{.spec.containers[?(@.name=="istio-proxy")].ports}'`) — use `status-port` or `agent` in the PodMonitor.
   - **OpenShift Service Mesh** may also configure scraping automatically; the PodMonitors above ensure the gateway is scraped even when it does not.

---

## 5. Grafana dashboard JSON (manual import)

If you do not use the Grafana Operator, you can import the dashboard manually:

1. Open **`observability/grafana-dashboard-nfl-wallet-environments.json`** in the repository.
2. In Grafana, go to **Dashboards** → **Import**, then upload the file or paste its contents.
3. Select the **Prometheus** datasource that scrapes your mesh and save the dashboard.

The dashboard shows the same panels as described in section 2 (request rate, response codes, latency, error rate, etc.) with an **Environment (namespace)** variable.

---

## 6. Testing Blue/Green (nfl-wallet-bluegreen) and viewing traces in Jaeger

The **nfl-wallet-bluegreen** HTTPRoute splits traffic between prod and test using a **dedicated canary hostname** (e.g. `nfl-wallet-canary.apps.<cluster-domain>`). It is only created when `nfl-wallet.blueGreen.enabled` is `true` in `nfl-wallet-prod/helm-values.yaml`.

![Blue/Green canary – traffic split](canary-blue-green.png)

*Figure: Blue/Green canary — traffic to the canary hostname is split between prod and test backends.*

![Blue/Green canary – traffic split (2)](canary-blue-green-2.png)

*Figure: Blue/Green canary — weight-based routing (e.g. 90% prod, 10% test).*

The **HTTPRoute** and **ReferenceGrant** are applied when you sync the prod and test apps (no extra step). For the canary hostname to work, the **gateway must be externalized** for that host: an OpenShift Route (or similar) with host = `nfl-wallet.blueGreen.hostname` must forward to the prod Gateway so the HTTPRoute can receive traffic. See [Gateway policies – Blue/Green](gateway-policies.md#bluegreen-with-test-and-prod-namespaces).

### 6.1 Verifying the Blue/Green HTTPRoute

**Check that the route exists:**

```bash
kubectl get httproute -n nfl-wallet-prod nfl-wallet-bluegreen
```

**Test the canary hostname** (same APIs as prod, but ~90% traffic to prod backends and ~10% to test). Use the API key as for prod:

```bash
# Use the managed cluster domain (see §6.4 if using ACM), not the hub
export CLUSTER_DOMAIN="cluster-h625z.h625z.sandbox613.opentlc.com"
export CANARY_HOST="nfl-wallet-canary.apps.${CLUSTER_DOMAIN}"
curl -s -H "X-Api-Key: nfl-wallet-customers-key" "https://${CANARY_HOST}/api/customers"
```

Or use the script with the canary target: `CANARY_HOST="nfl-wallet-canary.apps.<your-domain>" ./observability/run-tests.sh canary`

### 6.2 Viewing traces in Jaeger

If Jaeger (or Tempo with Jaeger UI) is installed, you can see **distributed traces** for requests that go through the Istio gateway. For example:

- **Jaeger UI:** `https://tempo-jaeger-http.apps.<cluster-domain>/search`  
  Example: [https://tempo-jaeger-http.apps.cluster-g62mw.dynamic.redhatworkshops.io/search](https://tempo-jaeger-http.apps.cluster-g62mw.dynamic.redhatworkshops.io/search)

In Jaeger:

1. Choose **Service** (e.g. `nfl-wallet-gateway-istio.nfl-wallet-prod.svc.cluster.local` or the service name for your gateway).
2. Click **Find Traces**. You should see traces for requests sent to the gateway host (prod, test, or canary).
3. To generate traces, run traffic first: `./observability/run-tests.sh loop` or `./observability/run-tests.sh canary`.

Traces appear only when the **Istio proxy (sidecar)** is present on the gateway and workload pods and telemetry is sent to your Jaeger/Tempo collector.

### 6.3 Fixing “Istio sidecar container not found in Pod(s)”

If Kiali or Jaeger show that the sidecar is missing, the namespaces must be **enabled for Istio injection**. Label the NFL Wallet namespaces and restart the workloads so new pods get the sidecar:

```bash
# Enable sidecar injection on the mesh namespaces
kubectl label namespace nfl-wallet-dev   istio-injection=enabled --overwrite
kubectl label namespace nfl-wallet-test istio-injection=enabled --overwrite
kubectl label namespace nfl-wallet-prod istio-injection=enabled --overwrite

# Restart deployments so new pods are created with the sidecar (adjust cluster/context if needed).
# Or run: ./scripts/label-istio-injection.sh --restart
for ns in nfl-wallet-dev nfl-wallet-test nfl-wallet-prod; do
  for d in $(kubectl get deployment -n "$ns" -o name 2>/dev/null); do kubectl rollout restart -n "$ns" "$d"; done
done
# If the gateway is a Deployment, it will get the sidecar on next rollout
kubectl get pods -n nfl-wallet-prod -l app=nfl-wallet-gateway-istio
# Each pod should show 2/2 containers (app + istio-proxy)
```

**Note:** With **revision-based injection** (e.g. OpenShift Service Mesh 2.x), the label may be `istio.io/rev=<revision>` instead of `istio-injection=enabled`. Check your mesh docs or run: `kubectl get namespace -l istio-injection --show-labels` on a namespace that already has injection.

After labeling and restarting, run the tests again and confirm in Kiali that the workload shows the proxy, and in Jaeger that traces appear for the gateway service.

### 6.4 Troubleshooting: HTTP 503 "Application is not available"

If the script returns **503** with the OpenShift "Application is not available" page, the route or its backend is not serving that host/path. Check:

1. **ACM: use the managed cluster domain, not the hub** — When you use ACM (`app-nfl-wallet-acm.yaml`), NFL Wallet runs on **managed clusters** (east, west). The gateway routes and hostnames live on those clusters. The **hub** (e.g. `cluster-g62mw.dynamic.redhatworkshops.io`) does **not** serve `nfl-wallet-prod.apps.cluster-g62mw...`; that host exists on the **managed** cluster. In the ApplicationSet list generator, each app has a `clusterDomain` (e.g. east: `cluster-h625z.h625z.sandbox613.opentlc.com`, west: `cluster-2l9nd.dynamic.redhatworkshops.io`). Use that domain when testing:
   ```bash
   # Example: test prod on the east managed cluster
   export CLUSTER_DOMAIN="cluster-h625z.h625z.sandbox613.opentlc.com"
   ./observability/run-tests.sh prod
   ```
   Or set `PROD_HOST`, `DEV_HOST`, `TEST_HOST` explicitly to the host shown by `oc get route -n nfl-wallet-prod` **on the managed cluster** (after `oc login` or `kubectl config use-context` to that cluster).

2. **Cluster and host** — The script uses `nfl-wallet-<env>.apps.<cluster-domain>`. Ensure `CLUSTER_DOMAIN` (or `DEV_HOST` / `TEST_HOST` / `PROD_HOST`) matches the cluster where the apps are deployed. If you use ACM with east/west, dev might be on a different cluster than prod; set the host for the cluster you are testing.

3. **Route exists and matches** — On the **target (managed) cluster**:
   ```bash
   oc get route -n nfl-wallet-dev  # (or test/prod)
   ```
   Confirm a route with the host you are curling (e.g. `nfl-wallet-dev.apps.<cluster-domain>`). If the route uses a different path (e.g. only `/api`), set `API_PATH` when running the script.

4. **Backend pods are running** — 503 often means no ready pods behind the route:
   ```bash
   oc get pods -n nfl-wallet-dev
   oc get gateway -n nfl-wallet-dev
   ```
   Ensure the gateway and API deployments have ready pods. If the gateway uses HTTPRoute (Istio), check that the HTTPRoute and Gateway have accepted status.

5. **Same cluster for all requests** — In the first run you may see 200 (e.g. from one cluster) and in `loop` see 503 if the default host points to another cluster where dev is not deployed. Set `CLUSTER_DOMAIN` or the `*_HOST` variables to the cluster you intend to test.

### 6.5 Troubleshooting: HTTP 401 Unauthorized (test and prod)

If **prod** or **canary** return **401** even when you send `X-Api-Key: nfl-wallet-customers-key`, the gateway (Kuadrant AuthPolicy) is rejecting the key. Common causes:

1. **API key Secrets not in kuadrant-system on the managed cluster** — Kuadrant expects API key Secrets in **`kuadrant-system`** on the **same cluster** as the gateway. The **Helm charts** (nfl-wallet-prod and nfl-wallet-test) create these Secrets via `templates/api-key-secrets-kuadrant.yaml` when `nfl-wallet.apiKeys.enabled` is true; sync the app on that cluster so they exist. Otherwise apply manually **on that cluster**:
   ```bash
   kubectl apply -f kuadrant-system/api-key-secrets.yaml
   ```
   Then check: `kubectl get secrets -n kuadrant-system -l 'api in (nfl-wallet-test, nfl-wallet-prod)'`

2. **Secret value does not match** — The script default is `nfl-wallet-customers-key`. The Secrets in `kuadrant-system/api-key-secrets.yaml` use `api_key: "nfl-wallet-customers-key"` (and similar for bills/raiders). If you overrode values in prod via Sealed Secrets or another mechanism, set `API_KEY_PROD` (and `API_KEY_TEST`) to the actual value:
   ```bash
   export API_KEY_PROD="<value from the Secret in kuadrant-system for nfl-wallet-prod>"
   ./observability/run-tests.sh prod
   ```


3. **Secrets on the wrong cluster** — The gateway that serves `nfl-wallet-prod.apps.cluster-s6krm...` runs on the **east** managed cluster. Authorino only reads Secrets from **that cluster's** `kuadrant-system`. If you applied on the **hub**, east has no Secrets. Switch to the managed cluster: `kubectl config use-context <east-context>`, then `kubectl apply -f kuadrant-system/api-key-secrets.yaml`. Confirm with `kubectl config current-context`.

4. **Authorino / AuthPolicy not ready** — On the managed cluster: `kubectl get authpolicy -n nfl-wallet-prod` and `kubectl get pods -n kuadrant-system -l app.kubernetes.io/name=authorino`. AuthPolicy must be accepted; Authorino must be running. Secret label `authorino.kuadrant.io/managed-by` must match the Authorino instance name (default `authorino`).

5. **Selector/labels** — AuthPolicy selector and Secret labels must match (e.g. `api: nfl-wallet-prod`). See [Gateway policies](gateway-policies.md#subscription-limit-dev-access-to-test-and-prod).

**Summary:** Dev returns 200 (no auth). If test/prod return 401, ensure the API key Secrets exist in **kuadrant-system** on the managed cluster—they are created by the Helm chart on sync, or apply `kuadrant-system/api-key-secrets.yaml` manually. Confirm context with `kubectl config current-context`.

---

## 7. Quick reference

| Resource | Location in repo |
|----------|------------------|
| Bash test script | `observability/run-tests.sh` |
| Grafana Operator YAMLs | `observability/grafana-operator/` |
| Grafana Operator README | `observability/grafana-operator/README.md` |
| Dashboard JSON (manual import) | `observability/grafana-dashboard-nfl-wallet-environments.json` |
| KIA1317 (Waypoint warning) | §4.0; optional waypoint via istioctl; namespace labels manual |
| Istio injection (one-time) | See §6.3 above or `scripts/label-istio-injection.sh` |
| 401 on test/prod/canary | See §6.5; apply `kuadrant-system/api-key-secrets.yaml` on the managed cluster |

All explanations above are in English and are intended for the GitHub Pages documentation site.
