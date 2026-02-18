# NFL Wallet GitOps

Documentation for the GitOps deployment of **NFL Stadium Wallet** on OpenShift with Argo CD, with optional Red Hat Advanced Cluster Management (ACM) or standalone east/west clusters.

---

## Documentation index

| Section | Description |
|--------|-------------|
| [**Architecture**](architecture.md) | Placements, ApplicationSets, multi-cluster scenarios (ACM and east/west with or without ACM). |
| [**Getting started**](getting-started.md) | Prerequisites, Helm dependencies, deployment steps (east/west and ACM). |
| [**Gateway policies**](gateway-policies.md) | Subscription / credential-based access (AuthPolicy) and Blue/Green (HTTPRoute) — where templates live and how to customize. |
| [**Observability**](observability.md) | Example curl commands to test APIs (traffic visible in Kiali), and Grafana dashboard for all environments (dev, test, prod). |
| [**Approval spec**](spec.md) | Success criteria for the Red Hat Connectivity Link and Service Mesh (Ambient) demo. |

---

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

---

## Repository structure

```
.
├── app-nfl-wallet-acm.yaml       # ACM Placements + ApplicationSet (when using ACM)
├── app-nfl-wallet-east.yaml     # ApplicationSet for east cluster (no ACM)
├── app-nfl-wallet-west.yaml     # ApplicationSet for west cluster (no ACM)
├── kuadrant.yaml                # Kuadrant CR (RateLimitPolicy / AuthPolicy)
├── gateway-policies/            # README for gateway policies (manifests in app templates)
├── observability/               # Curl examples + Grafana dashboard JSON
├── nfl-wallet-dev/              # Helm values + optional templates
├── nfl-wallet-test/             # Helm values + templates (AuthPolicy, ReferenceGrant)
├── nfl-wallet-prod/             # Helm values + templates (AuthPolicy, Blue/Green HTTPRoute)
├── docs/                        # This documentation (MkDocs / GitHub Pages)
└── scripts/                     # update-helm-deps.sh | .ps1
```

---

## Links

- [Chart on Artifact Hub](https://artifacthub.io/packages/helm/nfl-wallet/nfl-wallet)
- [Chart documentation (NFL-Wallet)](https://maximilianopizarro.github.io/NFL-Wallet/)
- [Source repository NFL-Wallet](https://github.com/maximilianoPizarro/NFL-Wallet)
- [Repository README (root)](https://github.com/maximilianoPizarro/nfl-wallet-gitops/blob/main/README.md)
