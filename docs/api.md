---
layout: default
title: API Reference
---

# API Reference

The Stadium Wallet backend is composed of three **.NET 8 ASP.NET Core APIs** deployed by the [Stadium Wallet chart](https://artifacthub.io/packages/helm/nfl-wallet/nfl-wallet). For full chart documentation, deployment options, and Connectivity Link, see:

**[Stadium Wallet — Chart documentation](https://maximilianopizarro.github.io/NFL-Wallet/)**

This page summarizes the **API section** as used in this GitOps repo (hosts, paths, and API keys per environment).

---

## APIs and endpoints

| API | Purpose | Path (Gateway) |
|-----|---------|----------------|
| **Customers** | Identity and customer list; link customers to team wallets | `/api-customers` |
| **Bills** | Buffalo Bills wallet — balances, transactions, pay, load | `/api-bills` |
| **Raiders** | Las Vegas Raiders wallet — balances, transactions, pay, load | `/api-raiders` |

The webapp talks to the gateway host (e.g. `nfl-wallet-dev.apps.<clusterDomain>`) and calls these paths. Dev does not require an API key; test and prod use `X-Api-Key` (see [Gateway policies](gateway-policies.md)).

---

## Base URL by environment

Per environment and cluster (east/west), the gateway host is:

| Environment | Host pattern | Example (single-cluster) |
|-------------|--------------|---------------------------|
| Dev | `nfl-wallet-dev.apps.<clusterDomain>` | `nfl-wallet-dev.apps.cluster-64k4b.64k4b.sandbox5146.opentlc.com` |
| Test | `nfl-wallet-test.apps.<clusterDomain>` | `nfl-wallet-test.apps.cluster-64k4b.64k4b.sandbox5146.opentlc.com` |
| Prod | `nfl-wallet-prod.apps.<clusterDomain>` | `nfl-wallet-prod.apps.cluster-64k4b.64k4b.sandbox5146.opentlc.com` |

Example: `GET https://nfl-wallet-dev.apps.<clusterDomain>/api-customers/Customers` (dev, no API key).

---

## API keys

Test and prod overlays include Secrets with default keys. Header: `X-Api-Key`.

| Environment | Key (customers) |
|-------------|-----------------|
| Test | `nfl-wallet-customers-key` |
| Prod | `nfl-wallet-customers-key` |

For production, use Sealed Secrets or External Secrets.

---

## Related documentation

| Topic | Where |
|-------|------|
| **Chart install, values, Connectivity Link** | [Stadium Wallet — Deployment](https://maximilianopizarro.github.io/NFL-Wallet/deployment) |
| **API keys and AuthPolicy** | [Gateway policies](gateway-policies.md) (this repo) |
| **Testing all APIs (east/west, dev/test/prod)** | [Observability](observability.md), [Scripts README](../scripts/README.md) |
