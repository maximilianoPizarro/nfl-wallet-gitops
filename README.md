# NFL Wallet – GitOps

GitOps deployment of the **NFL Stadium Wallet** stack ([Helm chart on Artifact Hub](https://artifacthub.io/packages/helm/nfl-wallet/nfl-wallet)) across three environments (**dev**, **test**, **prod**) using **Argo CD ApplicationSet**, with optional **Red Hat Advanced Cluster Management (ACM)** or standalone **east/west** clusters.

## Repository structure

```
.
├── app-nfl-wallet-acm.yaml       # ACM Placements + ApplicationSet (when using ACM)
├── app-nfl-wallet-east.yaml      # ApplicationSet for east cluster (no ACM)
├── app-nfl-wallet-west.yaml      # ApplicationSet for west cluster (no ACM)
├── kuadrant.yaml                 # Kuadrant CR (for RateLimitPolicy / AuthPolicy; apply on each cluster)
├── nfl-wallet-dev/               # Helm values for namespace nfl-wallet-dev
│   ├── Chart.yaml                # Wrapper chart depending on nfl-wallet
│   └── helm-values.yaml
├── nfl-wallet-test/              # Helm values for namespace nfl-wallet-test
│   ├── Chart.yaml
│   └── helm-values.yaml
├── nfl-wallet-prod/              # Helm values for namespace nfl-wallet-prod
│   ├── Chart.yaml
│   └── helm-values.yaml
├── docs/                         # Documentation for GitHub Pages
│   ├── index.md
│   ├── architecture.md
│   └── getting-started.md
├── scripts/
│   ├── update-helm-deps.sh
│   └── update-helm-deps.ps1
└── README.md
```

## Deployment options

| Option | File | Use case |
|--------|------|----------|
| **ACM** | `app-nfl-wallet-acm.yaml` | Hub with OpenShift GitOps + ACM; clusters selected by Placements. |
| **East (no ACM)** | `app-nfl-wallet-east.yaml` | Argo CD only; cluster registered as `east`. |
| **West (no ACM)** | `app-nfl-wallet-west.yaml` | Argo CD only; cluster registered as `west`. |

## East and West without ACM

Use the separate east and west files when you are **not** using ACM and want to deploy to one or both clusters independently.

**Prerequisites:**

- Argo CD with cluster(s) registered with names **exactly** `east` and/or `west`.

**Apply:**

```bash
# East only
kubectl apply -f app-nfl-wallet-east.yaml

# West only
kubectl apply -f app-nfl-wallet-west.yaml

# Both east and west
kubectl apply -f app-nfl-wallet-east.yaml -f app-nfl-wallet-west.yaml
```

- **app-nfl-wallet-east.yaml**: ApplicationSet `nfl-wallet-east` → deploys dev, test, and prod to the cluster named `east`.
- **app-nfl-wallet-west.yaml**: ApplicationSet `nfl-wallet-west` → deploys dev, test, and prod to the cluster named `west`.

Application names: `nfl-wallet-east-nfl-wallet-dev`, `nfl-wallet-west-nfl-wallet-test`, etc.

## ACM deployment

**Prerequisites:**

- **OpenShift GitOps** (Argo CD) and **ACM** on the hub.
- ConfigMap **acm-placement** in namespace `openshift-gitops` with cluster decisions for each Placement.
- Clusters registered in ACM with labels (e.g. `purpose=development|testing|production` or `region=east|west`).

**Apply:**

```bash
kubectl apply -f app-nfl-wallet-acm.yaml
```

See [docs/architecture.md](docs/architecture.md) for east/west mapping with Placements.

## Helm dependencies

Each `nfl-wallet-*` folder uses the [nfl-wallet](https://artifacthub.io/packages/helm/nfl-wallet/nfl-wallet) chart as a dependency. Before the first Argo CD sync, generate `charts/` and `Chart.lock`:

```bash
# From repo root (Linux/macOS)
./scripts/update-helm-deps.sh
```

Windows (PowerShell):

```powershell
.\scripts\update-helm-deps.ps1
```

Or manually:

```bash
helm repo add nfl-wallet https://maximilianopizarro.github.io/NFL-Wallet
helm repo update
for dir in nfl-wallet-dev nfl-wallet-test nfl-wallet-prod; do
  (cd "$dir" && helm dependency update)
done
```

Then commit `charts/` and `Chart.lock` in each folder.

## Repo URL

If the repo is under a different org or fork, set `source.repoURL` in `app-nfl-wallet-acm.yaml`, `app-nfl-wallet-east.yaml`, and `app-nfl-wallet-west.yaml`:

```yaml
source:
  repoURL: https://github.com/YOUR_ORG/nfl-wallet-gitops.git
```

## Environments and values

| Environment | Namespace        | Description |
|-------------|------------------|-------------|
| dev         | `nfl-wallet-dev` | Webapp + APIs + Gateway; no API keys or RHOBS by default |
| test        | `nfl-wallet-test`| Same as dev with rate limit on api-bills |
| prod        | `nfl-wallet-prod`| API keys, AuthorizationPolicy, RateLimitPolicy, and RHOBS enabled |

Full values are in `nfl-wallet-*/helm-values.yaml`. For **prod**, set `apiKeys.customers`, `apiKeys.bills`, and `apiKeys.raiders` (e.g. via Sealed Secrets or External Secrets).

## Documentation

- [docs/index.md](docs/index.md) – Overview and index  
- [docs/architecture.md](docs/architecture.md) – ACM/Argo architecture and east/west (with and without ACM)  
- [docs/getting-started.md](docs/getting-started.md) – Setup and deployment steps  

The `docs/` folder is set up for **GitHub Pages**. With MkDocs:

```bash
pip install mkdocs mkdocs-material
mkdocs serve       # local preview
mkdocs gh-deploy   # publish to gh-pages branch
```

Config file: `mkdocs.yml` in the repo root.

## Kuadrant (rate limiting / auth)

The NFL Wallet chart can use **Kuadrant** `RateLimitPolicy` and `AuthPolicy`. If Kuadrant is not installed yet, install the [Kuadrant operator](https://docs.kuadrant.io/kuadrant-operator/) (Gateway API, cert-manager, and Istio or Envoy Gateway are prerequisites), then apply the Kuadrant CR:

```bash
kubectl apply -f kuadrant.yaml
```

This creates the `Kuadrant` resource in `kuadrant-system` with observability enabled. For Redis-backed rate limiting, create a secret and patch the Limitador CR as per [Kuadrant docs](https://docs.kuadrant.io/limitador/doc/server/configuration/).

## References

- [NFL Wallet Helm chart](https://artifacthub.io/packages/helm/nfl-wallet/nfl-wallet)
- [Chart documentation](https://maximilianopizarro.github.io/NFL-Wallet/)
- [ApplicationSet + ACM example (librechat)](https://github.com/maximilianoPizarro/moodle-gitops/blob/main/app-librechat-acm.yaml)
