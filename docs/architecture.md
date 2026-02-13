# Architecture

## Components

- **OpenShift GitOps (Argo CD)**: syncs Git state to clusters.
- **ACM (Advanced Cluster Management)** (optional): manages multiple clusters and exposes which clusters satisfy each **Placement** via cluster decision resources.
- **ApplicationSet**: generates multiple Argo CD **Applications** from a matrix (environments × clusters).

## Deployment modes

### 1. With ACM (`app-nfl-wallet-acm.yaml`)

1. Apply `app-nfl-wallet-acm.yaml` on the hub. It defines:
   - **Placements**: `nfl-wallet-dev-placement`, `nfl-wallet-test-placement`, `nfl-wallet-prod-placement`.
   - **ApplicationSet** `nfl-wallet` with a matrix generator:
     - **List**: three elements (dev, test, prod) with `path`, `namespace`, and `placementName`.
     - **clusterDecisionResource**: reads ConfigMap `acm-placement` and filters by `placementName` to get the clusters for each environment.

2. For each (environment, cluster) pair, an Application is created (e.g. `nfl-wallet-east-1`).

3. Each Application points at the repo **path** for that environment (`nfl-wallet-dev`, `nfl-wallet-test`, `nfl-wallet-prod`). Those paths contain a Helm chart that depends on **nfl-wallet** and a `helm-values.yaml` per environment.

4. Argo CD runs `helm template` (after resolving dependencies) and applies resources to the target **namespace** and **cluster**.

### 2. East and West without ACM (separate files)

Use this when you do **not** use ACM and want to manage **east** and **west** clusters separately.

- **app-nfl-wallet-east.yaml**: ApplicationSet `nfl-wallet-east` → matrix of (dev, test, prod) × cluster named `east`.
- **app-nfl-wallet-west.yaml**: ApplicationSet `nfl-wallet-west` → matrix of (dev, test, prod) × cluster named `west`.
- Clusters must be registered in Argo CD with names exactly **east** and **west**.
- Apply only the file(s) you need (e.g. east only, west only, or both).
- Application names: `nfl-wallet-east-nfl-wallet-dev`, `nfl-wallet-west-nfl-wallet-test`, etc.

No Placements or ConfigMap `acm-placement` are required.

## East / West with ACM (label-based)

When using ACM, you can map clusters **east** and **west** via labels.

### Option: `purpose` label

- **east**: `purpose=development` and/or `purpose=testing`.
- **west**: `purpose=production` and/or `purpose=testing`.

Default Placements use `purpose`:

- `nfl-wallet-dev-placement` → `purpose=development`
- `nfl-wallet-test-placement` → `purpose=testing`
- `nfl-wallet-prod-placement` → `purpose=production`

Example outcome: dev on east only, test on east and west, prod on west only.

### Option: `region` label

1. Label clusters: `region=east`, `region=west`.
2. Edit the `predicates` of each Placement in `app-nfl-wallet-acm.yaml`:

**Dev on east only:**

```yaml
spec:
  predicates:
    - requiredClusterSelector:
        labelSelector:
          matchExpressions:
            - key: region
              operator: In
              values:
                - east
```

**Prod on west only:**

```yaml
spec:
  predicates:
    - requiredClusterSelector:
        labelSelector:
          matchExpressions:
            - key: region
              operator: In
              values:
                - west
```

**Test on both east and west:**

```yaml
spec:
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

### Combining `region` and `purpose`

You can use multiple `matchExpressions` in the same Placement (AND logic) to restrict to e.g. “east clusters with purpose=development”.

## Simplified diagram (ACM)

```
                    Hub (OpenShift GitOps + ACM)
    ┌─────────────────────────────────────────────────────────┐
    │  app-nfl-wallet-acm.yaml                                 │
    │  ┌─────────────┐  ┌──────────────────────────────────┐  │
    │  │ Placements  │  │ ApplicationSet (matrix)            │  │
    │  │ dev/test/   │  │ list (dev, test, prod) ×           │  │
    │  │ prod        │  │ clusterDecisionResource (ACM)      │  │
    │  └──────┬──────┘  └──────────────┬───────────────────┘  │
    │         │                         │                      │
    │         └────────────┬────────────┘                      │
    │                      ▼                                     │
    │         Applications: nfl-wallet-<clusterName>           │
    │         source: this repo, path: nfl-wallet-{dev|test|prod}
    └──────────────────────┬──────────────────────────────────┘
                           │
         ┌─────────────────┼─────────────────┐
         ▼                 ▼                 ▼
    Cluster east     Cluster west     (other clusters if any)
    nfl-wallet-dev   nfl-wallet-prod
    nfl-wallet-test  nfl-wallet-test
```

## ConfigMap acm-placement (ACM only)

The ACM ApplicationSet uses `clusterDecisionResource` with `configMapRef: acm-placement`. That ConfigMap must exist in `openshift-gitops` and be updated by ACM (or a controller that reads PlacementDecisions) with the list of clusters that satisfy each Placement. The structure and the label `cluster.open-cluster-management.io/placement: "{{placementName}}"` must match what the Argo CD ApplicationSet clusterDecisionResource generator expects. See ACM and OpenShift GitOps documentation for the exact format in your version.
