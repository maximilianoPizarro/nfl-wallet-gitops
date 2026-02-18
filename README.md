# NFL Wallet – GitOps

GitOps deployment of the **NFL Stadium Wallet** stack ([Helm chart on Artifact Hub](https://artifacthub.io/packages/helm/nfl-wallet/nfl-wallet)) across three environments (**dev**, **test**, **prod**) using **Argo CD ApplicationSet**, with optional **Red Hat Advanced Cluster Management (ACM)** or standalone **east/west** clusters.

## Repository structure

```
.
├── app-nfl-wallet-acm.yaml       # ACM Placements + ApplicationSet (when using ACM)
├── app-nfl-wallet-east.yaml      # ApplicationSet for east cluster (no ACM)
├── app-nfl-wallet-west.yaml      # ApplicationSet for west cluster (no ACM)
├── kuadrant.yaml                 # Kuadrant CR (for RateLimitPolicy / AuthPolicy; apply on each cluster)
├── gateway-policies/            # README for gateway policies (manifests live in app templates)
├── observability/               # run-tests.sh, Grafana Operator YAMLs, dashboard JSON
│   ├── README.md
│   ├── run-tests.sh            # Bash script to run API tests (dev/test/prod/loop)
│   ├── grafana-operator/       # Grafana, GrafanaDatasource, GrafanaDashboard CRs
│   └── grafana-dashboard-nfl-wallet-environments.json
├── nfl-wallet-dev/               # Helm values for namespace nfl-wallet-dev
│   ├── Chart.yaml                # Wrapper chart depending on nfl-wallet
│   └── helm-values.yaml
├── nfl-wallet-test/              # Helm values + templates (AuthPolicy, ReferenceGrant)
│   ├── Chart.yaml
│   ├── helm-values.yaml
│   └── templates/
│       ├── auth-policy.yaml
│       └── reference-grant.yaml
├── nfl-wallet-prod/              # Helm values + templates (AuthPolicy, Blue/Green HTTPRoute)
│   ├── Chart.yaml
│   ├── helm-values.yaml
│   └── templates/
│       ├── auth-policy.yaml
│       └── bluegreen-httproute.yaml
├── docs/                         # Documentation for GitHub Pages
│   ├── index.md
│   ├── architecture.md
│   └── getting-started.md
├── scripts/
│   └── update-helm-deps.sh
└── README.md
```

## Deployment options

| Option | File | Use case |
|--------|------|----------|
| **ACM** | `app-nfl-wallet-acm.yaml` | Hub with OpenShift GitOps + ACM; clusters selected by Placements. |
| **East (no ACM)** | `app-nfl-wallet-east.yaml` | Argo CD only; generates 3 apps (dev, test, prod). Set `server` in the file for east cluster. |
| **West (no ACM)** | `app-nfl-wallet-west.yaml` | Argo CD only; generates 3 apps (dev, test, prod). Set `server` in the file for west cluster. |

## East and West without ACM

Use the separate east and west files when you are **not** using ACM. No labels required; each ApplicationSet only uses a **list** generator and generates the 3 applications (dev, test, prod).

**Prerequisites:** None (no cluster labels). Default `server` is `https://kubernetes.default.svc` (in-cluster). For a remote cluster, edit the `server` value in the `list.elements` section of each file.

**Apply:**

```bash
# East only
kubectl apply -f app-nfl-wallet-east.yaml

# West only
kubectl apply -f app-nfl-wallet-west.yaml

# Both east and west
kubectl apply -f app-nfl-wallet-east.yaml -f app-nfl-wallet-west.yaml
```

- **app-nfl-wallet-east.yaml**: Generates `nfl-wallet-east-nfl-wallet-dev`, `nfl-wallet-east-nfl-wallet-test`, `nfl-wallet-east-nfl-wallet-prod` targeting the `server` defined in the file.
- **app-nfl-wallet-west.yaml**: Same for west; edit `server` in the file to point to your west cluster API URL.

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
# From repo root (Linux/macOS, Git Bash, WSL)
./scripts/update-helm-deps.sh
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

Full values are in `nfl-wallet-*/helm-values.yaml`. All values are under the top-level **`nfl-wallet`** key so the dependency subchart receives them (needed for Gateway and HTTPRoute creation). The dev/test/prod values cover API publication hostnames, credential-based access, rate limiting, and observability. For **test** and **prod**, set `nfl-wallet.apiKeys.customers`, `bills`, and `raiders` (e.g. via Sealed Secrets or External Secrets).

## Documentation

- [docs/index.md](docs/index.md) – Overview and index  
- [docs/architecture.md](docs/architecture.md) – ACM/Argo architecture and east/west (with and without ACM)  
- [docs/getting-started.md](docs/getting-started.md) – Setup and deployment steps  
- [observability/README.md](observability/README.md) – Example curl commands to test APIs (visible in Kiali) and Grafana dashboard for all environments (dev, test, prod)  

The `docs/` folder is set up for **GitHub Pages**. With MkDocs:

```bash
pip install mkdocs mkdocs-material
mkdocs serve       # local preview
mkdocs gh-deploy   # publish to gh-pages branch
```

Config file: `mkdocs.yml` in the repo root.

Alternatively, use **Jekyll** (layout, CSS, navigation like [NFL-Wallet/docs](https://github.com/maximilianoPizarro/NFL-Wallet/tree/main/docs)): in the repo **Settings → Pages**, choose "Deploy from a branch" and select the **/docs** folder. The `docs/` folder contains `_config.yml`, `_layouts/default.html`, and `assets/css/style.css` for the same structure and navigation.

## Kuadrant (rate limiting / auth)

The NFL Wallet chart can use **Kuadrant** `RateLimitPolicy` and `AuthPolicy`. If Kuadrant is not installed yet, install the [Kuadrant operator](https://docs.kuadrant.io/kuadrant-operator/) (Gateway API, cert-manager, and Istio or Envoy Gateway are prerequisites), then apply the Kuadrant CR:

```bash
kubectl apply -f kuadrant.yaml
```

This creates the `Kuadrant` resource in `kuadrant-system` with observability enabled. For Redis-backed rate limiting, create a secret and patch the Limitador CR as per [Kuadrant docs](https://docs.kuadrant.io/limitador/doc/server/configuration/).

### Gateway policies (subscription and Blue/Green)

Gateway policies for Spec §6 (subscription / credential-based access) and §12 (Blue/Green) are **Helm templates** in each app folder and deploy with the app when Argo CD syncs:

- **nfl-wallet-test/templates/:** AuthPolicy (API key required; label `api: nfl-wallet-test` on secrets) and ReferenceGrant (allows prod HTTPRoute to reference test Services).
- **nfl-wallet-prod/templates/:** AuthPolicy (API key required; label `api: nfl-wallet-prod` on secrets) and Blue/Green HTTPRoute (weight split between prod and test).

Label API key Secrets in test and prod with `api: <namespace>` so the AuthPolicy can find them. See [gateway-policies/README.md](gateway-policies/README.md) for details and customization.

## References

- [NFL Wallet Helm chart](https://artifacthub.io/packages/helm/nfl-wallet/nfl-wallet)
- [Chart documentation](https://maximilianopizarro.github.io/NFL-Wallet/)
- [ApplicationSet + ACM example (librechat)](https://github.com/maximilianoPizarro/moodle-gitops/blob/main/app-librechat-acm.yaml)
