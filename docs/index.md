# NFL Wallet GitOps

Documentation for the GitOps deployment of **NFL Stadium Wallet** on OpenShift with Argo CD, with optional Red Hat Advanced Cluster Management (ACM) or standalone east/west clusters.

## Contents

- **[Architecture](architecture.md)** – Placements, ApplicationSets, and multi-cluster scenarios (ACM and east/west without ACM).
- **[Getting started](getting-started.md)** – Prerequisites, Helm dependencies, and deployment steps.

## Summary

This repository deploys the NFL Wallet stack (Vue webapp + .NET APIs: customers, bills, raiders) to three namespaces:

| Environment | Namespace        |
|-------------|------------------|
| Dev         | `nfl-wallet-dev` |
| Test        | `nfl-wallet-test`|
| Prod        | `nfl-wallet-prod`|

The Helm chart used is [nfl-wallet on Artifact Hub](https://artifacthub.io/packages/helm/nfl-wallet/nfl-wallet). Values per environment live in `nfl-wallet-dev/`, `nfl-wallet-test/`, and `nfl-wallet-prod/` and are deployed via **ApplicationSet(s)**:

- **With ACM**: one ApplicationSet driven by Placements and cluster decisions.
- **Without ACM**: separate ApplicationSets for **east** and **west** clusters (see `app-nfl-wallet-east.yaml` and `app-nfl-wallet-west.yaml`).

## Links

- [Chart on Artifact Hub](https://artifacthub.io/packages/helm/nfl-wallet/nfl-wallet)
- [Chart documentation (NFL-Wallet)](https://maximilianopizarro.github.io/NFL-Wallet/)
- [Source repository NFL-Wallet](https://github.com/maximilianoPizarro/NFL-Wallet)
