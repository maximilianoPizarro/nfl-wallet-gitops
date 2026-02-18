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

### 40x on dashboard or public-dashboards URL

If you get **404** or **403** on `/api/dashboards/uid/.../public-dashboards` (or similar): do not use the public-dashboards link. Log in to Grafana with **admin** and the password from the Secret, then open **Dashboards** and select **NFL Wallet – All environments**. Public dashboards must be enabled and the dashboard shared as public in the UI; this repo does not configure that.
