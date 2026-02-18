# Getting Started

## Prerequisites

- **For ACM**: Hub cluster with **OpenShift GitOps** (Argo CD) and **Red Hat Advanced Cluster Management (ACM)**. Managed clusters registered in ACM with labels (e.g. `purpose`, `region`) as in [Architecture](architecture.md). ConfigMap **acm-placement** in namespace `openshift-gitops` so the ApplicationSet can resolve clusters per Placement.
- **For east/west without ACM**: No cluster registration or labels required. Optionally edit the `server` field in each ApplicationSet file to target a remote cluster (default is in-cluster).
- `helm` 3.x locally (to generate `charts/` and `Chart.lock`).

## Steps

### 1. Clone the repository

```bash
git clone https://github.com/maximilianoPizarro/nfl-wallet-gitops.git
cd nfl-wallet-gitops
```

### 2. Resolve Helm dependencies

Each environment folder (`nfl-wallet-dev`, `nfl-wallet-test`, `nfl-wallet-prod`) declares the [nfl-wallet](https://artifacthub.io/packages/helm/nfl-wallet/nfl-wallet) chart as a dependency. Argo CD needs the packaged charts in `charts/`.

From the repo root:

```bash
helm repo add nfl-wallet https://maximilianopizarro.github.io/NFL-Wallet
helm repo update

for dir in nfl-wallet-dev nfl-wallet-test nfl-wallet-prod; do
  (cd "$dir" && helm dependency update)
done
```

Or run `./scripts/update-helm-deps.sh` (or `.\scripts\update-helm-deps.ps1` on Windows). Ensure each `nfl-wallet-*/` has `charts/nfl-wallet-0.1.1.tgz` and `Chart.lock`, then commit them.

### 3. Set the repository URL in ApplicationSet(s)

If the repo is under a different org or fork, set `spec.template.spec.source.repoURL` in `app-nfl-wallet-acm.yaml`, `app-nfl-wallet-east.yaml`, and `app-nfl-wallet-west.yaml`:

```yaml
source:
  repoURL: https://github.com/YOUR_ORG/nfl-wallet-gitops.git
  targetRevision: main
  path: "{{path}}"
```

### 4a. Deploy with east/west (no ACM)

No labels or cluster registration needed. Edit `server` in each file if not using in-cluster, then:

```bash
# East only, west only, or both:
kubectl apply -f app-nfl-wallet-east.yaml
kubectl apply -f app-nfl-wallet-west.yaml
```

Check ApplicationSets and generated Applications:

```bash
kubectl get applicationset -n openshift-gitops
kubectl get applications -n openshift-gitops -l app.kubernetes.io/part-of=application-lifecycle
```

### 4b. Deploy with ACM

**Import managed clusters (east/west):** If you need to register managed clusters with the hub, use the template `acm-managed-cluster-template.yaml`. It contains `ManagedCluster` and `KlusterletAddonConfig` examples with comments on how to fill each field. Set `metadata.name` and labels (e.g. `region: east` or `region: west`) so Placements in `app-nfl-wallet-acm.yaml` can select them. Apply the template (or your edited copy) on the hub after the clusters are joined.

With `kubectl` targeting the hub:

```bash
kubectl apply -f app-nfl-wallet-acm.yaml
```

Verify Placements and ApplicationSet:

```bash
kubectl get placement -n openshift-gitops
kubectl get applicationset -n openshift-gitops
```

After a short delay, Argo CD will create Applications (one per environment × cluster). List them:

```bash
kubectl get applications -n openshift-gitops -l app.kubernetes.io/part-of=application-lifecycle
```

### 5. Sync and cluster names

If an Application is **OutOfSync**, sync from the Argo CD UI or:

```bash
argocd app sync nfl-wallet-<clusterName>
# or for east/west: nfl-wallet-east-nfl-wallet-dev, etc.
```

### 6. Cluster domain (ACM and multi-cluster)

The **apps cluster domain** (e.g. `cluster-lzdjz.lzdjz.sandbox1796.opentlc.com`) is used to build gateway and webapp hosts: `<namespace>.apps.<clusterDomain>`. Each env’s `helm-values.yaml` sets `nfl-wallet.clusterDomain` and the full host strings. When deploying with **ACM** (`app-nfl-wallet-acm.yaml`), the ApplicationSet overrides these via **Helm parameters** from the list generator: each element has `clusterDomain`, and the template passes `nfl-wallet.clusterDomain`, `nfl-wallet.gateway.route.host`, `nfl-wallet.webapp.route.host`, and `nfl-wallet.blueGreen.hostname`. To use a different domain per environment or per cluster, change `clusterDomain` in the list elements (or add list entries with different `clusterDomain` for each target cluster).

### 7. Values and secrets per environment

- **Dev/Test**: The included `helm-values.yaml` files are enough for a working deployment; you can enable or disable API keys and observability as needed.
- **Prod**: In `nfl-wallet-prod/helm-values.yaml`, `apiKeys.enabled` and `authorizationPolicy.enabled` are on. Set `apiKeys.customers`, `apiKeys.bills`, and `apiKeys.raiders` securely (e.g. Sealed Secrets, External Secrets, or Argo CD secrets backend).

### 8. GitHub Pages (optional)

The `docs/` folder is intended for static documentation. To publish with **MkDocs**:

1. Install: `pip install mkdocs mkdocs-material`.
2. From the repo root, use the root `mkdocs.yml` that references `docs/`.
3. Configure GitHub Pages to serve the MkDocs output (e.g. `mkdocs gh-deploy`).

For other generators (Jekyll, Docusaurus, etc.), point GitHub Pages at `docs/` or the generator’s output directory.
