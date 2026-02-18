# Grafana Operator – NFL Wallet observability

YAML manifests to use with the **Grafana Operator** so you can visualize NFL Wallet traffic (dev, test, prod) in Grafana. Prerequisite: [Grafana Operator](https://grafana.github.io/grafana-operator/) installed in the cluster.

## Contents

| File | Description |
|------|--------------|
| `namespace.yaml` | Namespace for Grafana and related resources (optional; use your existing Grafana ns if you prefer). |
| `grafana-instance.yaml` | **Grafana** CR – deploys a Grafana instance with label `dashboards: nfl-wallet`. Omit if you already have a Grafana and add this label to it (or adjust `instanceSelector` in datasource/dashboard). |
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

## Customization

- **Prometheus URL:** Edit `grafana-datasource-prometheus.yaml` → `spec.datasource.url` to point to the Prometheus that scrapes Istio (e.g. in `openshift-monitoring` or your observability namespace).
- **Namespace:** Change `metadata.namespace` in all resources to match your Grafana Operator / Grafana namespace.
- **Instance selector:** If your Grafana has a different label, set `spec.instanceSelector.matchLabels` in the datasource and dashboard to match it (e.g. `dashboards: grafana`).
