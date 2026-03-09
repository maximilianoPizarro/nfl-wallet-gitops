---
layout: default
title: ARGO-ACM-DEPLOY
---

# Deploy with Argo CD and ACM

Guide for deploying Stadium Wallet with Argo CD, with or without ACM (Advanced Cluster Management).

## File summary

| File | Purpose |
|------|---------|
| `argocd-placement-configmap.yaml` | ConfigMap `acm-placement` for clusterDecisionResource |
| `argocd-applicationset-rbac-placement.yaml` | RBAC for ApplicationSet to read PlacementDecisions |
| `app-nfl-wallet-acm.yaml` | Placements + GitOpsCluster (ACM only) |
| `app-nfl-wallet-acm-cluster-decision.yaml` | ApplicationSet (list generator, default) |
| `app-nfl-wallet-acm-cluster-decision-placement.yaml` | ApplicationSet with clusterDecisionResource (optional) |
| `app-nfl-wallet-east.yaml` | ApplicationSet for east cluster (no ACM) |
| `app-nfl-wallet-west.yaml` | ApplicationSet for west cluster (no ACM) |

## ACM logic (clusterDecisionResource)

```
                    ┌─────────────────────────────────────┐
                    │  Placement "nfl-wallet-gitops-        │
                    │  placement" (app-nfl-wallet-acm.yaml)│
                    │  - Selects clusters with              │
                    │    region=east or region=west         │
                    └─────────────────┬───────────────────┘
                                      │
                                      ▼
                    ┌─────────────────────────────────────┐
                    │  PlacementDecision                   │
                    │  status.decisions:                   │
                    │  - { clusterName: "east" }           │
                    │  - { clusterName: "west" }            │
                    └─────────────────┬───────────────────┘
                                      │
                                      ▼
                    ┌─────────────────────────────────────┐
                    │  ApplicationSet (clusterDecision    │
                    │  Resource generator)                  │
                    │  - Reads acm-placement ConfigMap     │
                    │  - Matrix: clusters × (dev,test,prod) │
                    │  - Generates 6 Applications          │
                    └─────────────────┬───────────────────┘
                                      │
                    ┌─────────────────┴─────────────────┐
                    ▼                                   ▼
         nfl-wallet-dev-east              nfl-wallet-dev-west
         nfl-wallet-test-east             nfl-wallet-test-west
         nfl-wallet-prod-east             nfl-wallet-prod-west
```

## Application order

### With ACM (hub + managed clusters east/west)

**Default (list generator):**
```bash
# 1. Placements + GitOpsCluster (creates east/west secrets in Argo CD)
kubectl apply -f app-nfl-wallet-acm.yaml -n openshift-gitops

# 2. ApplicationSet (generates the 6 Applications)
kubectl apply -f app-nfl-wallet-acm-cluster-decision.yaml -n openshift-gitops
```

**Alternative (clusterDecisionResource, clusters from Placement):**
```bash
kubectl apply -f argocd-applicationset-rbac-placement.yaml
kubectl apply -f argocd-placement-configmap.yaml -n openshift-gitops
kubectl apply -f app-nfl-wallet-acm.yaml -n openshift-gitops
kubectl apply -f app-nfl-wallet-acm-cluster-decision-placement.yaml -n openshift-gitops
```

### Without ACM (single cluster or manual east/west)

```bash
# East (edit server in file if remote)
kubectl apply -f app-nfl-wallet-east.yaml -n openshift-gitops

# West (edit server in file)
kubectl apply -f app-nfl-wallet-west.yaml -n openshift-gitops
```

## Overlay structure (Kustomize)

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

## Cluster domains

Overlays have the domain hardcoded. To change:

- **Single-cluster** (dev, test, prod): edit the patch in `nfl-wallet/overlays/dev`, etc.
- **ACM east**: edit overlays `*-east` (default: `cluster-4cspb.4cspb.sandbox1414.opentlc.com`)
- **ACM west**: edit overlays `*-west` (default: `cluster-4q4c7.4q4c7.sandbox3802.opentlc.com`)

## Verification

```bash
# Generated Applications
kubectl get applications -n openshift-gitops | grep nfl-wallet

# PlacementDecision (with ACM)
kubectl get placementdecision -n openshift-gitops

# Cluster secrets in Argo CD
kubectl get secrets -n openshift-gitops -l argocd.argoproj.io/secret-type=cluster
```

## Note: Application (Gateway, webapp)

The `nfl-wallet/` overlays deploy **Routes, AuthPolicy, API keys, namespace-mesh**. The application (Gateway, webapp, backends) must be deployed separately, e.g. with the Stadium Wallet chart from Artifact Hub or from another repo.
