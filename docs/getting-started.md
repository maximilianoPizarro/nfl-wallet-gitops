---
layout: default
title: Getting Started
---

# Getting Started

## Prerequisites

- **For ACM**: Hub cluster with **OpenShift GitOps** (Argo CD) and **Red Hat Advanced Cluster Management (ACM)**. Managed clusters registered in ACM with labels `region=east` or `region=west`. ConfigMap **acm-placement** in namespace `openshift-gitops`.
- **For east/west without ACM**: No cluster registration or labels required. Optionally edit the `server` field in each ApplicationSet to target a remote cluster (default: in-cluster).
- **Application**: The `nfl-wallet/` overlays deploy Routes, AuthPolicy, API keys. The application (Gateway, webapp, backends) must be deployed separately, e.g. with the [nfl-wallet chart](https://artifacthub.io/packages/helm/nfl-wallet/nfl-wallet) from Artifact Hub.

## Steps

### 1. Clone the repository

```bash
git clone https://github.com/maximilianoPizarro/nfl-wallet-gitops.git
cd nfl-wallet-gitops
```

### 2. Set the repo URL in ApplicationSet(s)

If the repo is under a different org or fork, edit `spec.template.spec.source.repoURL` in the ApplicationSet files:

```yaml
source:
  repoURL: https://github.com/YOUR_ORG/nfl-wallet-gitops.git
  targetRevision: main
  path: "{{path}}"   # or "nfl-wallet/overlays/dev" etc.
```

### 3. Verify Kustomize works

```bash
kubectl kustomize nfl-wallet/overlays/dev
kubectl kustomize nfl-wallet/overlays/prod
```

### 4a. Deploy with east/west (no ACM)

No labels or cluster registration needed. Edit `server` in each file if not using in-cluster, then:

```bash
# East, west, or both:
kubectl apply -f app-nfl-wallet-east.yaml -n openshift-gitops
kubectl apply -f app-nfl-wallet-west.yaml -n openshift-gitops
```

Verify ApplicationSets and generated Applications:

```bash
kubectl get applicationset -n openshift-gitops
kubectl get applications -n openshift-gitops -l app.kubernetes.io/part-of=application-lifecycle
```

### 4b. Deploy with ACM

**GitOps only on the hub:** Argo CD runs on the hub and deploys directly to managed clusters (east, west) using cluster secrets created by GitOpsCluster. You do **not** need to install OpenShift GitOps on east or west.

**RBAC on managed clusters:** The Argo CD application controller uses a token that authenticates on each managed cluster. For it to create/patch resources (HTTPRoutes, AuthPolicy, Secrets, etc.), grant cluster-admin on **each managed cluster** (east and west). Apply on the managed cluster (not the hub): `oc apply -f docs/managed-cluster-argocd-rbac.yaml`.

**Import managed clusters (east/west):** Use the template `acm-managed-cluster-template.yaml` to register clusters. Set `metadata.name` and labels (e.g. `region: east` or `region: west`) so the Placement selects them.

**Application order** (with kubectl targeting the hub):

```bash
# 1. RBAC for PlacementDecision
kubectl apply -f argocd-applicationset-rbac-placement.yaml

# 2. ConfigMap acm-placement
kubectl apply -f argocd-placement-configmap.yaml -n openshift-gitops

# 3. Placements + GitOpsCluster
kubectl apply -f app-nfl-wallet-acm.yaml -n openshift-gitops

# 4. ApplicationSet (generates the 6 Applications)
kubectl apply -f app-nfl-wallet-acm-cluster-decision.yaml -n openshift-gitops
```

See [ARGO-ACM-DEPLOY](ARGO-ACM-DEPLOY.md) for more details.

Verify Placements and ApplicationSet:

```bash
kubectl get placement -n openshift-gitops
kubectl get applicationset -n openshift-gitops
```

After a few seconds, Argo CD will create the Applications. List them:

```bash
kubectl get applications -n openshift-gitops -l app.kubernetes.io/part-of=application-lifecycle
```

**If Applications are not created:** See [argocd-applicationset-fix](argocd-applicationset-fix.md) and the troubleshooting section in [ARGO-ACM-DEPLOY](ARGO-ACM-DEPLOY.md).

### 5. Sync and cluster names

If an Application is **OutOfSync**, sync from the Argo CD UI or:

```bash
argocd app sync nfl-wallet-nfl-wallet-dev-east
# or for east/west without ACM: nfl-wallet-east-nfl-wallet-dev, etc.
```

### 6. Cluster domain

Overlays have the domain hardcoded in the Route patches. To change:

- **Single-cluster**: edit the patch in `nfl-wallet/overlays/dev`, `test`, `prod`.
- **ACM east**: edit overlays `*-east` (default: `cluster-thmg4.thmg4.sandbox4076.opentlc.com`).
- **ACM west**: edit overlays `*-west` (default: `cluster-2tjvj.2tjvj.sandbox5367.opentlc.com`).

### 7. API keys and secrets

Test and prod overlays include API key Secrets in the manifests. For production, use **Sealed Secrets** or **External Secrets**; do not commit real keys.

### 8. GitHub Pages (optional)

The `docs/` folder is intended for static documentation. To publish with MkDocs or Jekyll, see the repo README.
