---
layout: default
title: Architecture
---

# Architecture

![High level architecture](high%20leve%20architecture.png)

## Components

- **OpenShift GitOps (Argo CD)**: syncs Git state to clusters.
- **ACM (Advanced Cluster Management)** (optional): manages multiple clusters and exposes which clusters satisfy each **Placement** via cluster decision resources.
- **ApplicationSet**: generates multiple Argo CD **Applications** from a matrix (environments × clusters).
- **Kustomize**: overlays in `nfl-wallet/` deploy Routes, AuthPolicy, API keys, and namespace-mesh.

## Deployment modes

### 1. With ACM

1. Apply `app-nfl-wallet-acm.yaml` on the hub. It defines:
   - **ManagedClusterSetBinding**: binds cluster set `global` to `openshift-gitops`.
   - **Placement** `nfl-wallet-gitops-placement`: selects clusters with `region=east` or `region=west`.
   - **GitOpsCluster**: registers managed clusters in Argo CD (creates east/west secrets).

2. Apply `app-nfl-wallet-acm-cluster-decision.yaml`. It defines:
   - **ApplicationSet** `nfl-wallet` with matrix generator:
     - **clusterDecisionResource**: reads ConfigMap `acm-placement` and gets clusters from Placement.
     - **list**: three elements (dev, test, prod) with `path` and `namespace`.

3. For each (environment, cluster) pair, an Application is created (e.g. `nfl-wallet-dev-east`, `nfl-wallet-prod-west`).

4. Each Application points to the **path** of the corresponding Kustomize overlay (`nfl-wallet/overlays/dev-east`, `nfl-wallet/overlays/prod-west`, etc.).

5. Argo CD runs `kustomize build` and applies resources to the target **namespace** and **cluster**.

### 2. East and West without ACM (separate files)

Use when **not** using ACM and managing east and west independently.

- **app-nfl-wallet-east.yaml**: ApplicationSet `nfl-wallet-east` → list generator; generates 3 Applications (dev, test, prod). Target cluster via `server` (default: `https://kubernetes.default.svc` in-cluster).
- **app-nfl-wallet-west.yaml**: Same for west; edit `server` for the west cluster API.
- Application names: `nfl-wallet-east-nfl-wallet-dev`, `nfl-wallet-west-nfl-wallet-test`, etc.

No Placements, ConfigMap, or cluster labels required.

## East / West with ACM (labels)

With ACM, clusters are mapped via labels `region=east` or `region=west`.

### Placement `nfl-wallet-gitops-placement`

The current Placement selects clusters with:

```yaml
predicates:
  - requiredClusterSelector:
      labelSelector:
        matchExpressions:
          - key: region
            operator: In
            values:
              - east
              - west
```

Result: dev, test, and prod deploy on **both** clusters (east and west). To restrict (e.g. dev only on east, prod only on west), create separate Placements per environment and adjust the ApplicationSet.

## Simplified diagram (ACM)

```
                    Hub (OpenShift GitOps + ACM)
    ┌─────────────────────────────────────────────────────────┐
    │  app-nfl-wallet-acm.yaml                                 │
    │  ┌─────────────┐  ┌──────────────────────────────────┐  │
    │  │ Placement   │  │ GitOpsCluster                     │  │
    │  │ nfl-wallet- │  │ (creates east/west secrets)        │  │
    │  │ gitops-     │  │                                    │  │
    │  │ placement   │  └──────────────────────────────────┘  │
    │  └──────┬──────┘                                        │
    │         │                                                │
    │  app-nfl-wallet-acm-cluster-decision.yaml                │
    │  ┌──────────────────────────────────────────────────┐   │
    │  │ ApplicationSet (matrix)                           │   │
    │  │ clusterDecisionResource × list (dev, test, prod)   │   │
    │  └──────────────┬───────────────────────────────────┘   │
    │                 │                                        │
    │                 ▼                                        │
    │  Applications: nfl-wallet-<namespace>-<clusterName>      │
    │  source: path nfl-wallet/overlays/<env>-<cluster>        │
    └──────────────────────┬──────────────────────────────────┘
                            │
         ┌──────────────────┼──────────────────┐
         ▼                  ▼                  ▼
    Cluster east       Cluster west
    nfl-wallet-dev     nfl-wallet-dev
    nfl-wallet-test    nfl-wallet-test
    nfl-wallet-prod    nfl-wallet-prod
```

## ConfigMap acm-placement (ACM only)

The ApplicationSet uses `clusterDecisionResource` with `configMapRef: acm-placement`. That ConfigMap must exist in `openshift-gitops` and defines the duck type so ApplicationSet can read `status.decisions[].clusterName` from PlacementDecisions.

Apply with: `kubectl apply -f argocd-placement-configmap.yaml -n openshift-gitops`

## Kustomize overlay structure

| Path | Use |
|------|-----|
| `nfl-wallet/overlays/dev` | Single-cluster dev |
| `nfl-wallet/overlays/test` | Single-cluster test |
| `nfl-wallet/overlays/prod` | Single-cluster prod |
| `nfl-wallet/overlays/dev-east` | ACM: dev on east cluster |
| `nfl-wallet/overlays/dev-west` | ACM: dev on west cluster |
| `nfl-wallet/overlays/test-east` | ACM: test on east cluster |
| `nfl-wallet/overlays/test-west` | ACM: test on west cluster |
| `nfl-wallet/overlays/prod-east` | ACM: prod on east cluster |
| `nfl-wallet/overlays/prod-west` | ACM: prod on west cluster |
