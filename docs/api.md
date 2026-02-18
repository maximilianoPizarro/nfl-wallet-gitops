# API Reference

The NFL Stadium Wallet backend is composed of three **.NET 8 ASP.NET Core APIs** deployed by the [nfl-wallet Helm chart](https://artifacthub.io/packages/helm/nfl-wallet/nfl-wallet). For full chart documentation, deployment options, and Connectivity Link (Gateway API, HTTPRoutes, security), see the **NFL Stadium Wallet** site:

**[NFL Stadium Wallet — Chart documentation](https://maximilianopizarro.github.io/NFL-Wallet/)**

That site (Jekyll) covers Architecture, Deployment, Connectivity Link, Security, and Observability. This page summarizes the **API section** as used in this GitOps repo (hosts, paths, and API keys per environment).

---

## APIs and endpoints

| API | Purpose | Image | Path (Gateway) |
|-----|---------|-------|----------------|
| **Customers** | Identity and customer list; link customers to team wallets | `nfl-wallet-api-customers` | `/api/customers` |
| **Bills** | Buffalo Bills wallet — balances, transactions, pay, load | `nfl-api-bills` | `/api/bills` |
| **Raiders** | Las Vegas Raiders wallet — balances, transactions, pay, load | `nfl-wallet-api-raiders` | `/api/raiders` |

The webapp talks to the gateway host (e.g. `nfl-wallet-dev.apps.<clusterDomain>`) and calls these paths. Dev has no API key; test and prod use `X-Api-Key` (see [Gateway policies](gateway-policies.md)).

---

## Base URL by environment

Per environment and cluster (east/west), the gateway host is:

| Environment | Host pattern | Example (east) |
|-------------|--------------|----------------|
| Dev | `nfl-wallet-dev.apps.<clusterDomain>` | `nfl-wallet-dev.apps.cluster-s6krm.s6krm.sandbox3480.opentlc.com` |
| Test | `nfl-wallet-test.apps.<clusterDomain>` | `nfl-wallet-test.apps.cluster-s6krm.s6krm.sandbox3480.opentlc.com` |
| Prod | `nfl-wallet-prod.apps.<clusterDomain>` | `nfl-wallet-prod.apps.cluster-s6krm.s6krm.sandbox3480.opentlc.com` |

Example: `GET https://nfl-wallet-dev.apps.<clusterDomain>/api/customers` (dev, no API key).

---

## Related documentation

| Topic | Where |
|-------|--------|
| **Chart install, values, Connectivity Link** | [NFL Stadium Wallet — Deployment](https://maximilianopizarro.github.io/NFL-Wallet/deployment), [Connectivity Link](https://maximilianopizarro.github.io/NFL-Wallet/connectivity-link) |
| **API keys and AuthPolicy** | [NFL Stadium Wallet — Security](https://maximilianopizarro.github.io/NFL-Wallet/security), [Gateway policies](gateway-policies.md) (this repo) |
| **Testing all APIs (east/west, dev/test/prod)** | [Scripts README — Test APIs](../scripts/README.md#test-scripts-for-nfl-wallet-apis-east--west) |
