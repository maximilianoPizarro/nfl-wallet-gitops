# Stadium Wallet Observability

Grafana Operator, dashboard, and datasource for Stadium Wallet (dev, test, prod), from [nfl-wallet-gitops/observability](../observability).

The Grafana Route host is overridden with the connectivity-link cluster domain (`cluster-rddww.dynamic.redhatworkshops.io`).

## Deployment

The ApplicationSet `nfl-wallet-observability` deploys this app to the `openshift-cluster-observability-operator` namespace.

To change the cluster domain, edit the patch in `kustomization.yaml` (Route `/spec/host` path).

## Requirements

- Grafana Operator installed
- **Observability** app synced (MonitoringStack + ServiceMonitors for nfl-wallet-test/prod gateways)
- The datasource is patched to use `connectivity-link-stack-prometheus` (in-cluster) instead of the default Promxy/ACM URL
- The dashboard is patched for single-cluster (removed `cluster` filter; metrics may not have that label)

## Troubleshooting: no data in dashboard

1. **Debug panel** – The dashboard has a "[Debug] Total request rate (all namespaces)" panel. If it shows data, metrics are being scraped; if empty, the ServiceMonitors may not be finding targets.
2. **Verify Prometheus targets** – In Prometheus UI (port-forward or route), check Status → Targets. Ensure `nfl-wallet-*-gateway-metrics` and `nfl-wallet-*-waypoint-metrics` show UP.
3. **Verify Service labels** – Istio Gateway API Services must have `gateway.networking.k8s.io/gateway-name`:
   ```bash
   kubectl get svc -n nfl-wallet-prod -l gateway.networking.k8s.io/gateway-name
   kubectl get svc -n nfl-wallet-test -l gateway.networking.k8s.io/gateway-name
   ```
4. **Generate traffic** – Send requests to the gateways so metrics exist:
   ```bash
   curl -H "X-Api-Key: nfl-wallet-customers-key" https://nfl-wallet-test.apps.cluster-4cspb.4cspb.sandbox1414.opentlc.com/api-customers/Customers
   curl -H "X-Api-Key: nfl-wallet-customers-key" https://nfl-wallet-prod.apps.cluster-4cspb.4cspb.sandbox1414.opentlc.com/api-customers/Customers
   ```
5. **Check metric names in Grafana Explore** – Run `istio_requests_total` or `istio_requests_total{reporter=~"source|destination"}` to confirm metrics exist and inspect labels (`destination_workload_namespace`, `destination_service_namespace`).
