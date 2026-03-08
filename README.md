# Stadium Wallet – GitOps

GitOps deployment of the **Stadium Wallet** stack ([Helm chart on Artifact Hub](https://artifacthub.io/packages/helm/nfl-wallet/nfl-wallet)) across three environments (**dev**, **test**, **prod**) using **Argo CD ApplicationSet**, with optional **Red Hat Advanced Cluster Management (ACM)** or standalone **east/west** clusters.

## Repository structure

```
.
├── app-nfl-wallet-acm.yaml              # Placements + GitOpsCluster (ACM)
├── app-nfl-wallet-acm-cluster-decision.yaml  # ApplicationSet (list generator)
├── app-nfl-wallet-east.yaml      # ApplicationSet east (without ACM)
├── app-nfl-wallet-west.yaml      # ApplicationSet west (without ACM)
├── argocd-placement-configmap.yaml   # ConfigMap acm-placement
├── argocd-applicationset-rbac-placement.yaml
├── kuadrant.yaml                 # Kuadrant CR
├── nfl-wallet/                   # Kustomize (routes, AuthPolicy, API keys)
│   ├── base/                     # gateway route
│   ├── base-canary/              # canary route (prod)
│   └── overlays/                 # dev, test, prod + dev-east, dev-west, etc.
├── nfl-wallet-observability/     # Grafana + ServiceMonitors
├── observability/                # Grafana Operator base
├── developer-hub/catalog/nfl-wallet/  # Backstage catalog (Domain, System, Components, APIs)
├── docs/                         # Documentation
│   ├── index.md
│   ├── architecture.md
│   └── getting-started.md
└── README.md
```

## Deployment options

| Option | File | Use case |
|--------|------|----------|
| **ACM** | `app-nfl-wallet-acm.yaml` + `app-nfl-wallet-acm-cluster-decision.yaml` | Hub + ACM; 6 apps (dev/test/prod × east/west). See [docs/ARGO-ACM-DEPLOY.md](docs/ARGO-ACM-DEPLOY.md) |
| **East (no ACM)** | `app-nfl-wallet-east.yaml` | Argo CD; 3 apps (dev, test, prod). |
| **West (no ACM)** | `app-nfl-wallet-west.yaml` | Argo CD; 3 apps (dev, test, prod). Edit `server` for west cluster. |

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

See [docs/ARGO-ACM-DEPLOY.md](docs/ARGO-ACM-DEPLOY.md) for the application order and Placement logic.

```bash
kubectl apply -f argocd-applicationset-rbac-placement.yaml
kubectl apply -f argocd-placement-configmap.yaml -n openshift-gitops
kubectl apply -f app-nfl-wallet-acm.yaml -n openshift-gitops
kubectl apply -f app-nfl-wallet-acm-cluster-decision.yaml -n openshift-gitops
```

## Repo URL

If the repo is in another org or fork, edit `source.repoURL` in the ApplicationSets:

```yaml
source:
  repoURL: https://github.com/YOUR_ORG/nfl-wallet-gitops.git
```

## Environments

| Environment | Namespace        | Description |
|-------------|------------------|-------------|
| dev         | `nfl-wallet-dev` | Gateway route; no API keys |
| test        | `nfl-wallet-test`| Gateway + AuthPolicy + API keys + ESPN route |
| prod        | `nfl-wallet-prod`| Gateway + canary + AuthPolicy + API keys |

Each Application deploys **two sources**: (1) Kustomize overlays (namespace, Route, AuthPolicy, Secrets, etc.) and (2) the **Stadium Wallet Helm chart** from the HelmChartRepository (Deployments, Gateway, HTTPRoutes, webapp, APIs). Ensure the HelmChartRepository is configured in east and west (`helm-catalog/helm-repository-nfl-wallet.yaml`).

## Documentation

- [docs/index.md](docs/index.md) – Overview and index  
- [docs/architecture.md](docs/architecture.md) – ACM/Argo architecture and east/west (with and without ACM)  
- [docs/getting-started.md](docs/getting-started.md) – Setup and deployment steps  
- [docs/ARGO-ACM-DEPLOY.md](docs/ARGO-ACM-DEPLOY.md) – ACM logic and application order with Argo CD
- [observability/README.md](observability/README.md) – Grafana dashboard and curl to test APIs  

The `docs/` folder is set up for **GitHub Pages**. With MkDocs:

```bash
pip install mkdocs mkdocs-material
mkdocs serve       # local preview
mkdocs gh-deploy   # publish to gh-pages branch
```

Config file: `mkdocs.yml` in the repo root.

Alternatively, use **Jekyll** (layout, CSS, navigation like [Stadium Wallet docs](https://github.com/maximilianoPizarro/NFL-Wallet/tree/main/docs)): in the repo **Settings → Pages**, choose "Deploy from a branch" and select the **/docs** folder. The `docs/` folder contains `_config.yml`, `_layouts/default.html`, and `assets/css/style.css` for the same structure and navigation.

## Kuadrant (rate limiting / auth)

The Stadium Wallet chart can use **Kuadrant** `RateLimitPolicy` and `AuthPolicy`. If Kuadrant is not installed yet, install the [Kuadrant operator](https://docs.kuadrant.io/kuadrant-operator/) (Gateway API, cert-manager, and Istio or Envoy Gateway are prerequisites), then apply the Kuadrant CR:

```bash
kubectl apply -f kuadrant.yaml
```

This creates the `Kuadrant` resource in `kuadrant-system` with observability enabled. For Redis-backed rate limiting, create a secret and patch the Limitador CR as per [Kuadrant docs](https://docs.kuadrant.io/limitador/doc/server/configuration/).

### Gateway policies

AuthPolicy and API keys are in `nfl-wallet/overlays/test` and `nfl-wallet/overlays/prod`. API key Secrets have label `api: nfl-wallet-test` or `api: nfl-wallet-prod`. See [nfl-wallet/README.md](nfl-wallet/README.md).

## References

- [Stadium Wallet Helm chart](https://artifacthub.io/packages/helm/nfl-wallet/nfl-wallet)
- [Chart documentation](https://maximilianopizarro.github.io/NFL-Wallet/)
- [ApplicationSet + ACM example (librechat)](https://github.com/maximilianoPizarro/moodle-gitops/blob/main/app-librechat-acm.yaml)
