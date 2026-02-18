# Observability

Observability for NFL Wallet (Kiali traffic visibility and Grafana dashboards) is documented in the **observability** folder at the repository root.

## Contents

- **[Observability README](../observability/README.md)** – Full documentation:
  - **Example curl commands** to call the APIs for dev (no auth), test and prod (with API key), so that traffic is visible in **Kiali**.
  - How to **view traffic in Kiali** (namespace/app filters).
  - **Grafana dashboard** that aggregates metrics for **all environments** (dev, test, prod): request rate, response codes, latency, error rate, and per-service traffic.

## Quick links

| Resource | Location |
|----------|----------|
| Curl examples (dev / test / prod) | [observability/README.md](../observability/README.md#1-example-api-calls-curl) |
| Kiali traffic visibility | [observability/README.md](../observability/README.md#2-viewing-traffic-in-kiali) |
| Grafana dashboard (all envs) | [observability/grafana-dashboard-nfl-wallet-environments.json](../observability/grafana-dashboard-nfl-wallet-environments.json) |

Import the JSON dashboard in Grafana and select the Prometheus datasource that scrapes Istio metrics. Use the **Environment (namespace)** variable to filter by `nfl-wallet-dev`, `nfl-wallet-test`, or `nfl-wallet-prod`, or view all at once.
