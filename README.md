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
kubectl apply -f app-kuadrant-resources.yaml -n openshift-gitops
```

## Repo URL

If the repo is in another org or fork, edit `source.repoURL` in the ApplicationSets:

```yaml
source:
  repoURL: https://github.com/YOUR_ORG/nfl-wallet-gitops.git
```

## Environments

| Environment | Namespace        | Chart version | Description |
|-------------|------------------|---------------|-------------|
| dev         | `nfl-wallet-dev` | **0.1.3** | Gateway route + RHBK biometric login (NeuroFace) |
| test        | `nfl-wallet-test`| **0.1.3** | Gateway + AuthPolicy + API keys + ESPN route + RHBK biometric login + OIDC policy |
| prod        | `nfl-wallet-prod`| **0.1.1** | Gateway + canary + AuthPolicy + API keys (no biometric login) |

Each Application deploys **two sources**: (1) Kustomize overlays (namespace, Route, AuthPolicy, Secrets, etc.) and (2) the **Stadium Wallet Helm chart** from the HelmChartRepository (Deployments, Gateway, HTTPRoutes, webapp, APIs). Ensure the HelmChartRepository is configured in east and west (`helm-catalog/helm-repository-nfl-wallet.yaml`).

### Biometric login (dev / test — chart 0.1.3)

Chart version **0.1.3** includes [RHBK (Red Hat Build of Keycloak)](https://github.com/maximilianoPizarro/rhbk-biometric-flow) with [NeuroFace](https://github.com/maximilianoPizarro/neuroface) biometric facial authentication as an optional dependency (`rhbk-neuroface.enabled`). The ApplicationSet enables it for **dev** and **test** with a camera resolution of **1920 × 1080** (FHD).

RHBK login URLs follow the pattern `nfl-wallet-rhbk-neuroface-<namespace>.apps.<cluster-domain>`:

| Environment | East | West |
|-------------|------|------|
| dev | `nfl-wallet-rhbk-neuroface-nfl-wallet-dev.apps.cluster-64k4b.64k4b.sandbox5146.opentlc.com` | `nfl-wallet-rhbk-neuroface-nfl-wallet-dev.apps.cluster-7rt9h.7rt9h.sandbox1900.opentlc.com` |
| test | `nfl-wallet-rhbk-neuroface-nfl-wallet-test.apps.cluster-64k4b.64k4b.sandbox5146.opentlc.com` | `nfl-wallet-rhbk-neuroface-nfl-wallet-test.apps.cluster-7rt9h.7rt9h.sandbox1900.opentlc.com` |

### OIDC policy (test only)

In **test**, the chart's `gateway.oidcPolicy` is enabled. This creates Kuadrant AuthPolicy objects (one per API HTTPRoute) that validate OIDC JWT tokens issued by the RHBK realm. The OIDC policies target individual HTTPRoutes (`api-customers`, `api-bills`, `api-raiders`) and coexist with the existing **API key AuthPolicy** on the Gateway (which remains unchanged in the overlay). The OIDC issuer URL is `https://nfl-wallet-rhbk-neuroface-nfl-wallet-test.apps.<cluster-domain>/realms/neuroface`.

### Canary testing (0.1.3 on prod URLs)

Prod overlays include a **canary Route** (`nfl-wallet-canary.apps.<cluster-domain>`). To test chart **0.1.3** with biometric login in a prod context:

1. Change `chartVersion` from `"0.1.1"` to `"0.1.3"` for the prod entry in the ApplicationSet.
2. Add the RHBK Helm values (copy from the dev/test conditional block).
3. Push and let Argo CD sync. Access the canary URL from the browser to verify the biometric login.
4. If approved, keep `0.1.3`. If not, revert `chartVersion` to `"0.1.1"` and push again.

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

### Resource requirements (Authorino, Limitador, Gateway)

Default operator resources (100m CPU / 32Mi RAM) cause **20s+ latency** on the ext-authz call from the gateway to Authorino, especially in sandboxes with mTLS enabled. These are deployed **automatically via GitOps** with the `kuadrant-resources` ApplicationSet:

```bash
# On the hub — after applying the nfl-wallet ApplicationSet:
kubectl apply -f app-kuadrant-resources.yaml -n openshift-gitops
```

This creates 2 Applications (`kuadrant-resources-east`, `kuadrant-resources-west`) that deploy resource patches to both clusters using `ServerSideApply`:

| Component | CPU request | Memory request | CPU limit | Memory limit |
|-----------|-----------|--------------|---------|------------|
| **Authorino** | 500m | 256Mi | 2 | 1Gi |
| **Limitador** | 250m | 128Mi | 1 | 256Mi |
| **Gateway proxy** (test + prod) | 500m | 256Mi | 2 | 1Gi |

Resources are in `kuadrant-system/` (Kustomize). ArgoCD uses `selfHeal: true` so they're reapplied if operators reset them.

### Gateway policies

AuthPolicy and API keys are in `nfl-wallet/overlays/test` and `nfl-wallet/overlays/prod`. API key Secrets have label `api: nfl-wallet-test` or `api: nfl-wallet-prod`. See [nfl-wallet/README.md](nfl-wallet/README.md).

## References

- [Stadium Wallet Helm chart](https://artifacthub.io/packages/helm/nfl-wallet/nfl-wallet)
- [Chart documentation](https://maximilianopizarro.github.io/NFL-Wallet/)
- [ApplicationSet + ACM example (librechat)](https://github.com/maximilianoPizarro/moodle-gitops/blob/main/app-librechat-acm.yaml)
