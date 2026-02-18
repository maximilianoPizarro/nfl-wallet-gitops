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

**GitOps only on the hub:** This setup uses the **Push** model: Argo CD runs only on the hub and deploys directly to managed clusters (east, west) using the cluster secrets created by GitOpsCluster. You do **not** need to install OpenShift GitOps on the east or west clusters.

**RBAC on managed clusters:** The hub's Argo CD application controller uses a token that authenticates on each managed cluster as `system:serviceaccount:openshift-gitops:openshift-gitops-argocd-application-controller`. That service account (or the namespace) may be created by ACM when the cluster is registered for GitOps. So that it can create/patch resources (HTTPRoutes, AuthPolicy, Secrets, etc.), grant it cluster-admin on **each managed cluster** (east and west) once. Apply on the managed cluster (not the hub): `oc apply -f docs/managed-cluster-argocd-rbac.yaml`. Without this, sync fails with "cannot patch resource httproutes/... is forbidden".

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

**If the ApplicationSet shows "No se han creado aplicaciones" (no Applications created):** (1) **Prerequisites** — Apply `app-nfl-wallet-acm.yaml` so you have ManagedClusterSetBinding, GitOpsCluster, and its Placement (cluster secrets east/west must exist). (2) **ApplicationSet controller** — It must be running in `openshift-gitops` (e.g. `openshift-gitops-applicationset-controller`). Check: `kubectl get pods -n openshift-gitops | findstr applicationset`. If the pod is missing, enable the ApplicationSet component in the Argo CD instance: `oc patch argocd openshift-gitops -n openshift-gitops --type merge -p '{"spec":{"applicationSet":{}}}'`. (3) **Logs** — `kubectl logs -n openshift-gitops deployment/openshift-gitops-applicationset-controller --tail=100` for errors. (4) The **console message** can persist even when prerequisites are met; verify with `kubectl get applications -n openshift-gitops`. (5) If the ApplicationSet status says **"there are no clusters with this name: west"** (or east), Argo CD has no cluster secrets for east/west on the hub. GitOpsCluster normally creates them; if they are missing, create them manually using `docs/argocd-cluster-secrets-manual.yaml` (replace the bearer tokens with valid tokens for each managed cluster). (6) If **west** Applications show **"the server has asked for the client to provide credentials"**, the cluster secret for west on the hub has invalid or expired credentials; update that secret’s `config.bearerToken` with a valid token for the west cluster API (see `docs/argocd-cluster-secrets-manual.yaml`).

**Checklist (run on the hub):**

```bash
# 1. ApplicationSet controller running?
kubectl get pods -n openshift-gitops | findstr applicationset

# 2. If no applicationset pod: enable ApplicationSet in Argo CD
oc patch argocd openshift-gitops -n openshift-gitops --type merge -p '{"spec":{"applicationSet":{}}}'

# 3. Cluster secrets present (east, west)?
kubectl get secret -n openshift-gitops -l argocd.argoproj.io/secret-type=cluster

# 4. Applications created?
kubectl get applications -n openshift-gitops

# 5. Controller logs (if still no Applications)
kubectl logs -n openshift-gitops deployment/openshift-gitops-applicationset-controller --tail=100

# 6. If controller pod is Pending: check why (e.g. "Too many pods" = node at capacity)
kubectl describe pod -n openshift-gitops -l app.kubernetes.io/name=openshift-gitops-applicationset-controller
# To add capacity: add a worker node (scale MachineSet) or increase maxPods — see docs/add-cluster-capacity.md.
```

### 5. Sync and cluster names

If an Application is **OutOfSync**, sync from the Argo CD UI or:

```bash
argocd app sync nfl-wallet-<clusterName>
# or for east/west: nfl-wallet-east-nfl-wallet-dev, etc.
```

### 5b. ACM topology: cluster red, ApplicationSet yellow

In the **ACM topology view**, colors usually mean:

- **Green:** Resource healthy (cluster available, applications Synced and Healthy).
- **Yellow:** Warning (e.g. ApplicationSet with applications OutOfSync or Progressing, or ApplicationSet conditions in error).
- **Red:** Error (cluster unavailable/disconnected or applications failing).

**What to check so everything shows green:**

1. **Cluster red or AVAILABLE=Unknown**  
   On the hub: `kubectl get managedcluster -o wide`  
   Ensure the affected cluster has `AVAILABLE=True` (and `CONNECTED=True` if your version shows it). If **AVAILABLE** is **Unknown** while **JOINED** is True, the registration agent on the managed cluster is not updating its lease on the hub (often kube-apiserver unreachable or hub ↔ managed cluster connectivity).
   - Check conditions: `kubectl describe managedcluster <name>`. If you see **ManagedClusterConditionAvailable** with reason `ManagedClusterLeaseUpdateStopped` and message "Registration agent stopped updating its lease", the hub has marked the cluster **unreachable** (it will also add a taint `cluster.open-cluster-management.io/unreachable`).
   - **Fixes:** (1) Restore connectivity hub ↔ managed cluster (network, firewall, VPN). (2) On the **managed** cluster, ensure the klusterlet is running (e.g. `oc get pods -n open-cluster-management-agent`). (3) Restart the klusterlet so the registration agent re-establishes the lease: `oc rollout restart deployment/klusterlet-agent -n open-cluster-management-agent` and optionally `oc rollout restart deployment/klusterlet -n open-cluster-management-agent` (deployment names may vary; list with `oc get deploy -n open-cluster-management-agent`). Run these on **east2** and **west2** respectively, not on the hub. Once the agent can reach the hub again and update the lease, AVAILABLE will become True and the taint is removed.
   - To allow Placements to still select unreachable clusters (e.g. during transient outages), you can add tolerations to the Placement: see Red Hat docs "Configuring application placement tolerations for GitOps" (tolerate `cluster.open-cluster-management.io/unreachable` and `cluster.open-cluster-management.io/unavailable`).
   - In the ACM console: Infrastructure → Clusters → [cluster] → Details and Conditions tabs.

2. **ApplicationSet yellow**  
   ACM reflects Argo CD state (ApplicationSet and generated Applications). For it to turn green:
   - All Applications from the ApplicationSet must be **Synced** and **Healthy**.
   - On the hub: `kubectl get applications -n openshift-gitops -o custom-columns=NAME:.metadata.name,SYNC:.status.sync.status,HEALTH:.status.health.status`
   - Fix any that are OutOfSync or not Healthy (sync from the Argo CD UI, west cluster credentials, RBAC on managed clusters per `docs/managed-cluster-argocd-rbac.yaml`).
   - Check ApplicationSet conditions: `kubectl get applicationset nfl-wallet -n openshift-gitops -o jsonpath='{.status.conditions}'`

Once managed clusters are available and all Applications are Synced and Healthy, the ACM topology should show green after a refresh.

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
