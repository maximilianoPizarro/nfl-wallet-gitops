# Grafana Operator – NFL Wallet observability

YAML manifests to use with the **Grafana Operator** so you can visualize NFL Wallet traffic (dev, test, prod) in Grafana. Prerequisite: [Grafana Operator](https://grafana.github.io/grafana-operator/) installed in the cluster.

## Contents

| File | Description |
|------|--------------|
| `namespace.yaml` | Namespace for Grafana and related resources (optional; use your existing Grafana ns if you prefer). |
| `grafana-instance.yaml` | **Grafana** CR – deploys a Grafana instance with label `dashboards: nfl-wallet`. Omit if you already have a Grafana and add this label to it (or adjust `instanceSelector` in datasource/dashboard). |
| `grafana-route.yaml` | **OpenShift Route** – exposes the Grafana service at `https://<host>`. Edit `spec.host` for your cluster domain. Optional if the Grafana CR has `route.enabled: true`. |
| `grafana-datasource-prometheus.yaml` | **GrafanaDatasource** – Prometheus datasource for Istio/mesh metrics. Set `spec.datasource.url` to your Prometheus URL (e.g. `http://prometheus-operated.monitoring.svc:9090` or your Prometheus route). |
| `grafana-dashboard-configmap.yaml` | **ConfigMap** – NFL Wallet “All environments” dashboard JSON. |
| `grafana-dashboard-nfl-wallet.yaml` | **GrafanaDashboard** CR – references the ConfigMap so the dashboard is provisioned into Grafana. |

## Apply order

1. Create namespace (or use existing):  
   `kubectl apply -f namespace.yaml`
2. (Optional) Deploy Grafana instance:  
   `kubectl apply -f grafana-instance.yaml`
3. Set Prometheus URL in `grafana-datasource-prometheus.yaml`, then:  
   `kubectl apply -f grafana-datasource-prometheus.yaml`
4. Dashboard:  
   `kubectl apply -f grafana-dashboard-configmap.yaml`  
   `kubectl apply -f grafana-dashboard-nfl-wallet.yaml`

Or apply the whole folder (after editing the Prometheus URL):  
`kubectl apply -f observability/grafana-operator/`

## Accessing the Grafana console

- **OpenShift Route:** With `route.enabled: true` in `grafana-instance.yaml`, the operator creates a Route. View the URL:
  ```bash
  oc get route -n observability
  ```
  Open that URL in your browser. User **admin**; password in the Secret created by the operator:
  ```bash
  kubectl get secret -n observability -l app.kubernetes.io/name=grafana -o name
  kubectl get secret <secret-name> -n observability -o jsonpath='{.data.admin-password}' | base64 -d
  ```
- **Port-forward:** `kubectl port-forward -n observability svc/grafana-nfl-wallet 3000:3000` then open http://localhost:3000.

## Customization

- **Prometheus URL:** Edit `grafana-datasource-prometheus.yaml` → `spec.datasource.url` to point to the Prometheus that scrapes Istio (e.g. in `openshift-monitoring` or your observability namespace).
- **Namespace:** Change `metadata.namespace` in all resources to match your Grafana Operator / Grafana namespace.
- **Instance selector:** If your Grafana has a different label, set `spec.instanceSelector.matchLabels` in the datasource and dashboard to match it (e.g. `dashboards: grafana`).

## Troubleshooting

### 500 on Prometheus queries (datasource / query API)

If Grafana returns **500** when loading the dashboard or when you see errors like **"query range dial tcp ... no such host"**, the Prometheus datasource URL points to a host that does not exist or is unreachable in your cluster. The default URL (`prometheus-operated.monitoring.svc.cluster.local`) is only valid if you have Prometheus Operator in a namespace named `monitoring`.

**Fix:**

1. **Find Prometheus (or Thanos) in your cluster:**
   ```bash
   kubectl get svc -A | grep -E 'prometheus|thanos'
   ```

2. **Set the correct URL** in `grafana-datasource-prometheus.yaml` → `spec.datasource.url`:
   - Use the **in-cluster** service URL: `http://<service>.<namespace>.svc.cluster.local:<port>` (or `https://` if TLS).
   - Examples:
     - **OpenShift user workload monitoring:**  
       `http://prometheus-user-workload.openshift-user-workload-monitoring.svc.cluster.local:9090`
     - **Custom Prometheus in namespace `monitoring`:**  
       `http://prometheus-operated.monitoring.svc.cluster.local:9090`
     - **OpenShift platform (Thanos):**  
       `https://thanos-querier.openshift-monitoring.svc.cluster.local:9091` (may require TLS and/or token).

3. **Re-apply the datasource** and reload Grafana:
   ```bash
   kubectl apply -f observability/grafana-operator/grafana-datasource-prometheus.yaml
   ```
   In Grafana, go to **Connections → Data sources**, open Prometheus, click **Save & test**. If the namespace where Grafana runs cannot reach the Prometheus namespace, you may need a network policy or to run Grafana in the same namespace as Prometheus.

### No error but no data in the dashboard

If the datasource **Save & test** succeeds but the NFL Wallet dashboard shows **no data**, the Prometheus/Thanos instance you’re using likely **does not have Istio metrics** (e.g. it isn’t scraping the gateway or workload proxies in `nfl-wallet-dev`, `nfl-wallet-test`, `nfl-wallet-prod`).

**1. Check if Istio metrics exist**

In Grafana go to **Explore**, choose the Prometheus datasource, and run:

```promql
istio_requests_total
```

or:

```promql
count(istio_requests_total)
```

- If you get **no data** or **empty**: this store is not scraping Istio/Envoy. The Thanos (or Prometheus) behind the URL may be configured only for other targets (e.g. platform metrics), not the mesh.
- If you get **data**: check the labels (e.g. `destination_workload_namespace`, `reporter`). If label names differ from the dashboard (e.g. `destination_workload_namespace` vs `workload_namespace`), the dashboard panels won’t match; you’d need to adjust the queries in the dashboard JSON.

**2. Get Istio metrics into the store**

For the dashboard to show traffic by environment:

- **Prometheus (or the Prometheus that feeds Thanos) must scrape the Istio proxy metrics** from the gateway and, if you want per-workload detail, from the API pods. That usually means a **ServiceMonitor** (or **PodMonitor**) in each app namespace that selects the gateway (and optionally workloads) and scrapes the Istio telemetry port (e.g. **15020**, path `/stats/prometheus`). See [Making traffic visible in the service mesh](../../docs/observability.md#41-making-traffic-visible-in-the-service-mesh-kiali-and-grafana) for an example.
- **Send traffic through the gateway** so that metrics are generated: run `./observability/run-tests.sh all` (or curl to the gateway host). Then in Grafana set a time range that includes that period.

**3. If using a Thanos that doesn’t scrape the mesh**

If your working URL is a Thanos querier (e.g. in `openshift-cluster-observability-operator`) that has no Istio scrape config, you have two options:

- **Configure that observability stack** to scrape the Istio gateway/workloads (e.g. add the ServiceMonitors in the NFL Wallet namespaces and ensure the Prometheus that feeds Thanos uses them), or  
- **Use a Prometheus that does scrape the mesh** (e.g. OpenShift User Workload Monitoring’s Prometheus, once it can reach the mesh and has the right ServiceMonitors). Then point the Grafana datasource to that Prometheus (or its Thanos) instead.

### 400 on query (POST /api/ds/query) or on health check

If Grafana returns **400** when loading the dashboard or when running **Save & test** (health or query), the backend behind the datasource URL is rejecting the request.

- **Use the Thanos querier URL** that works in your cluster (e.g. `thanos-querier-...openshift-cluster-observability-operator.svc.cluster.local:10902`). The default in this repo is set to that; `prometheus-user-workload:9091` often returns 400 for Grafana’s queries.
- **Use GET for queries** — In the datasource, `jsonData.httpMethod` is set to **GET**. If you override it to POST and get 400, switch back to GET.
- **URL = base only** — No trailing path (no `/api`). See “400 on datasource health check” below.

### 400 on datasource health check (GET /api/datasources/uid/prometheus/health)

If Grafana returns **400** when you run **Save & test** on the Prometheus datasource (or when calling the health endpoint), the backend that the datasource URL points to may be rejecting the health-check request.

- **URL must be the base only** — No trailing path (e.g. use `http://...:9091`, not `http://...:9091/api`). Grafana appends `/api/v1/query` itself; a trailing path can cause 400.
- **Use the in-cluster service URL** — Not the Route (`.apps.`); see “401 or 400 when using a Route URL” below.
- **Try the other in-cluster endpoint** — If `prometheus-user-workload:9091` keeps returning 400, switch the datasource URL to the Thanos querier that works in your cluster (e.g. `http://thanos-querier-nfl-wallet-east-nfl-wallet-prod-thanos.openshift-cluster-observability-operator.svc.cluster.local:10902`). Then run **Save & test** again. The dashboard may still show no data until Istio is scraped (see “No error but no data”).

### 401 or 400 when using a Route URL (e.g. ...apps.cluster-...)

If the datasource URL is an **OpenShift Route** (host like `prometheus-user-workload-openshift-user-workload-monitoring.apps.<cluster-domain>` or `thanos-ruler-...apps...`), you may get **401 Unauthorized** or **400 Bad Request**. Routes are not intended for Prometheus API calls from Grafana and often reject or mishandle them.

**Fix:** Use the **in-cluster service URL** instead, so Grafana (running in the cluster) talks to the service directly and does not go through the Route:

- **Thanos Ruler** (openshift-user-workload-monitoring):  
  `http://thanos-ruler.openshift-user-workload-monitoring.svc.cluster.local:9091`  
  (Thanos Ruler is mainly for rules/alerts; for ad-hoc queries prefer Prometheus or Thanos Querier.)
- **Prometheus user workload**:  
  `http://prometheus-user-workload.openshift-user-workload-monitoring.svc.cluster.local:9091`

If you must use the Route (e.g. Grafana outside the cluster), configure the datasource with **Authentication** → **Basic auth** or **Bearer token** and a token that has access (e.g. OpenShift service account token).

### 40x on dashboard or public-dashboards URL

If you get **404** or **403** on `/api/dashboards/uid/.../public-dashboards` (or similar): do not use the public-dashboards link. Log in to Grafana with **admin** and the password from the Secret, then open **Dashboards** and select **NFL Wallet – All environments**. Public dashboards must be enabled and the dashboard shared as public in the UI; this repo does not configure that.
