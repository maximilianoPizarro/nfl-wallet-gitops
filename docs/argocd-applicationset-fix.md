---
layout: default
title: ApplicationSet Troubleshooting
---

# ApplicationSet – fix for controller errors

If the ApplicationSet controller reports an error or **"Must have required property 'clusterDecisionResource'"**, use the steps below.

**Quick checklist:**
1. Default: **`app-nfl-wallet-acm-cluster-decision.yaml`** uses list generator (no ConfigMap needed).
2. For clusterDecisionResource: use **`app-nfl-wallet-acm-cluster-decision-placement.yaml`** (requires ConfigMap + RBAC).
3. After applying the placement variant, the **first** generator in `spec.generators` must be `clusterDecisionResource` (verify with the command in the next section).
3. If the policy still fails, it may require **`spec.clusterDecisionResource`** (top-level). That does not exist in the ApplicationSet API; see the "If the error persists" paragraph below and share it with your admin.

## "Must have required property 'clusterDecisionResource'"

**If your ACM policy requires clusterDecisionResource:** The default **`app-nfl-wallet-acm-cluster-decision.yaml`** uses a **list** generator (no clusterDecisionResource). Use **`app-nfl-wallet-acm-cluster-decision-placement.yaml`** instead, which has `clusterDecisionResource` as the first generator. Apply ConfigMap + RBAC first (see section 2 below).

**Check first:** The file **`app-nfl-wallet-acm.yaml`** (Placements + GitOpsCluster) must be applied **before** the ApplicationSet.

**Force the correct structure:** If you need clusterDecisionResource, delete and re-apply the placement variant (after ConfigMap + RBAC):

```bash
kubectl delete applicationset nfl-wallet -n openshift-gitops
kubectl apply -f argocd-applicationset-rbac-placement.yaml
kubectl apply -f argocd-placement-configmap.yaml -n openshift-gitops
kubectl apply -f app-nfl-wallet-acm-cluster-decision-placement.yaml -n openshift-gitops
```

Verify the applied spec has `clusterDecisionResource` as the first generator:

```bash
kubectl get applicationset nfl-wallet -n openshift-gitops -o jsonpath='{.spec.generators[0]}' | head -c 200
```

You should see `"clusterDecisionResource":{...}`. If you see `"list":{...}` instead, the wrong file was applied or the cluster state overrode the generators order.

This error can also mean:

### 1. Invalid mix (one generator with both list and clusterDecisionResource)

The ApplicationSet CRD allows only **one** generator type per generator object. You cannot have both `list` and `clusterDecisionResource` in the **same** generator:

- **Correct:** one generator with only `list` (and no `clusterDecisionResource`).
- **Wrong:** one generator with both `list` and `clusterDecisionResource`.

**Fix:** For environments that do not require clusterDecisionResource, use `app-nfl-wallet-east.yaml` or `app-nfl-wallet-west.yaml` (list generator, 3 apps per cluster).

### 2. Policy requires a clusterDecisionResource generator

If your environment **requires** that the ApplicationSet use a `clusterDecisionResource` generator (e.g. ACM policy), use the variant that has it as a **separate** generator (matrix with list):

1. Apply **RBAC** so the ApplicationSet controller can list PlacementDecisions, then the ConfigMap and ApplicationSet:

```bash
kubectl apply -f argocd-applicationset-rbac-placement.yaml -n openshift-gitops
kubectl apply -f argocd-placement-configmap.yaml -n openshift-gitops
kubectl apply -f app-nfl-wallet-acm-cluster-decision.yaml -n openshift-gitops
```

The ConfigMap must be named `acm-placement` (`configMapRef: acm-placement`) and the `clusterDecisionResource` generator must include `requeueAfterSeconds`; otherwise policy validation fails. The **first** generator in the list must be `clusterDecisionResource` (with `configMapRef` and `requeueAfterSeconds`) so policy checks pass.

2. Apply **first** `app-nfl-wallet-acm.yaml` (Placements + GitOpsCluster) so that the PlacementDecision `nfl-wallet-gitops-placement-1` exists and lists east and west in `status.decisions`.

3. The ApplicationSet in `app-nfl-wallet-acm-cluster-decision.yaml` uses Kustomize (path `nfl-wallet/overlays/<env>-<cluster>`); not Helm.

In the variant, `clusterDecisionResource` is its own generator; it is **not** in the same object as `list`. The matrix produces 6 Applications (dev/test/prod × east/west).

**If the error persists:** The policy may be checking for **`spec.clusterDecisionResource`** (a top-level key under `spec`). The Argo CD ApplicationSet API **does not support that**. The API only has:

- `spec.generators[]` — array of generator objects
- each generator object has **one** key: either `list`, or `clusterDecisionResource`, or `git`, etc.

So the valid structure is **`spec.generators[0].clusterDecisionResource`**, not `spec.clusterDecisionResource`. You cannot add a top-level `spec.clusterDecisionResource` because the CRD would reject it as an unknown field.

**What to ask your platform/ACM admin:** Update the policy so it validates that **at least one element of `spec.generators`** has the key `clusterDecisionResource`, instead of requiring `spec.clusterDecisionResource`. For example (Gatekeeper/Rego-style idea): *"require that `spec.generators` contains an item that has the key `clusterDecisionResource`"* (e.g. check `spec.generators[i].clusterDecisionResource` for some `i`). Alternatively, grant an exception for the `nfl-wallet` ApplicationSet in `openshift-gitops`.

## No applications created (ApplicationSet generates 0 Applications)

If the ApplicationSet was applied but **no Applications appear** (dev-east, dev-west, etc.), run these checks on the **HUB**:

### 1. PlacementDecision must have decisions

The `clusterDecisionResource` generator reads `PlacementDecision` resources. If `status.decisions` is empty, no Applications are generated.

```bash
# List PlacementDecisions for nfl-wallet-gitops-placement
kubectl get placementdecision -n openshift-gitops -l cluster.open-cluster-management.io/placement=nfl-wallet-gitops-placement -o yaml

# Expected: status.decisions has at least one entry with clusterName (east or west)
kubectl get placementdecision -n openshift-gitops -l cluster.open-cluster-management.io/placement=nfl-wallet-gitops-placement -o jsonpath='{.items[*].status.decisions[*].clusterName}'
```

**If empty:** The Placement selects no clusters. Go to step 2.

### 2. ManagedClusters must have region=east or region=west

The Placement in `app-nfl-wallet-acm.yaml` selects clusters with `region=east` or `region=west`:

```bash
kubectl get managedcluster -o custom-columns=NAME:.metadata.name,LABELS:.metadata.labels
```

**Fix:** Add labels to your managed clusters:

```bash
kubectl label managedcluster east region=east --overwrite
kubectl label managedcluster west region=west --overwrite
```

If your clusters have different names (e.g. `cluster-4cspb`, `cluster-rddww`), add the region label and ensure the cluster **name** matches what you want in Argo CD destination (e.g. rename or use `cluster-4cspb` as destination if that is the secret name).

### 3. ManagedClusterSet "global" must exist

```bash
kubectl get managedclusterset
kubectl get managedclustersetbinding -n openshift-gitops
```

The `ManagedClusterSetBinding` binds `global` to `openshift-gitops`. If `global` does not exist, create it or use the correct cluster set name in `app-nfl-wallet-acm.yaml`.

### 4. GitOpsCluster and cluster secrets

GitOpsCluster creates Argo CD cluster secrets from the Placement. Wait 1–2 minutes after applying, then:

```bash
kubectl get secret -n openshift-gitops -l argocd.argoproj.io/secret-type=cluster
```

You should see `cluster-east` and `cluster-west` (or names matching your ManagedCluster names).

### 5. ApplicationSet controller logs

```bash
kubectl logs -n openshift-gitops deployment/openshift-gitops-applicationset-controller --tail=50
```

Look for errors about PlacementDecision, "forbidden", or "could not find".

### 6. "resources were not found" / "could not find the requested resource"

If the ApplicationSet controller logs show:
```text
resources were not found GVK="cluster.open-cluster-management.io/v1beta1, Resource=PlacementDecision"
failed to get dynamic resources: the server could not find the requested resource
```

**Fix:** The ConfigMap `acm-placement` must use the **resource name** (lowercase plural), not the Kind. Change `kind: PlacementDecision` to `kind: placementdecisions`:

```yaml
# argocd-placement-configmap.yaml
data:
  apiVersion: cluster.open-cluster-management.io/v1beta1
  kind: placementdecisions    # not PlacementDecision
  statusListKey: decisions
  matchKey: clusterName
```

Then re-apply and restart the controller:
```bash
kubectl apply -f argocd-placement-configmap.yaml -n openshift-gitops
kubectl rollout restart deployment/openshift-gitops-applicationset-controller -n openshift-gitops
```

### 7. Force refresh

After fixing Placement/ManagedClusters:

```bash
kubectl annotate applicationset nfl-wallet -n openshift-gitops argocd.argoproj.io/refresh=hard --overwrite
kubectl rollout restart deployment/openshift-gitops-applicationset-controller -n openshift-gitops
# Wait ~30s
kubectl get applications -n openshift-gitops | grep nfl-wallet
```

---

## PlacementDecision forbidden (RBAC)

**Recommended fix:** On the **HUB**, run the script that detects the exact resource name on your cluster and applies the RBAC:

```bash
# From the repo root
bash scripts/fix-applicationset-placement-rbac.sh
```

If the controller uses a different ServiceAccount, set it: `SA_NAME=actual-sa-name bash scripts/fix-applicationset-placement-rbac.sh`

---

If status shows:

```text
PlacementDecision.cluster.open-cluster-management.io is forbidden: User
"system:serviceaccount:openshift-gitops:openshift-gitops-applicationset-controller"
cannot list resource "PlacementDecision" in API group "cluster.open-cluster-management.io"
```

**Fix:** Apply the RBAC manifest on the **HUB**. The manifest uses **ClusterRole + ClusterRoleBinding** (cluster-scoped) so the GitOps operator does not remove the binding when it reconciles the `openshift-gitops` namespace. If you had an old RoleBinding, delete it first, then apply:

```bash
kubectl delete rolebinding ocm-placement-consumer-applicationset -n openshift-gitops --ignore-not-found
kubectl apply -f argocd-applicationset-rbac-placement.yaml
kubectl rollout restart deployment -n openshift-gitops -l app.kubernetes.io/name=applicationset-controller
```

**Verify (run on the HUB):**

```bash
# 1) ClusterRole and ClusterRoleBinding must exist
kubectl get clusterrole ocm-placement-consumer-openshift-gitops
kubectl get clusterrolebinding ocm-placement-consumer-applicationset-openshift-gitops -o yaml

# 2) This must print "yes"
kubectl auth can-i list placementdecisions.cluster.open-cluster-management.io -n openshift-gitops --as=system:serviceaccount:openshift-gitops:openshift-gitops-applicationset-controller

# 3) Restart the controller so it picks up permissions
kubectl rollout restart deployment -n openshift-gitops -l app.kubernetes.io/name=applicationset-controller
# If no deployment matches, find the ApplicationSet controller deployment name and restart it
kubectl get deployment -n openshift-gitops
```

**Important:** If `auth can-i` returns **yes** but the ApplicationSet still shows "forbidden", the controller pods are still using an **old token**. You must **restart the deployment** so new pods get an updated token. In OpenShift GitOps the deployment is usually named `openshift-gitops-applicationset-controller`:

```bash
# Restart the controller (typical name in OpenShift GitOps)
kubectl rollout restart deployment openshift-gitops-applicationset-controller -n openshift-gitops
kubectl rollout status deployment openshift-gitops-applicationset-controller -n openshift-gitops --timeout=120s
```

If the forbidden error persists, **delete the pod** to force a new one (the deployment will recreate it):

```bash
# List the applicationset-controller pod
kubectl get pods -n openshift-gitops -l app.kubernetes.io/name=applicationset-controller
# If no label, search by name:
kubectl get pods -n openshift-gitops | findstr applicationset

# Delete the pod (replace POD_NAME with the one that appears)
kubectl delete pod -n openshift-gitops -l app.kubernetes.io/name=applicationset-controller
# Or by name: kubectl delete pod openshift-gitops-applicationset-controller-xxxxx-yyyyy -n openshift-gitops
```

Verify the deployment uses the correct ServiceAccount: `kubectl get deployment openshift-gitops-applicationset-controller -n openshift-gitops -o jsonpath='{.spec.template.spec.serviceAccountName}'` (should be `openshift-gitops-applicationset-controller`).

Wait ~1 minute and check: `kubectl get applicationset nfl-wallet -n openshift-gitops` and status/conditions. If the ApplicationSet exists but **no Applications are created**, check the status message and that the PlacementDecision has the correct label:

```bash
kubectl get applicationset nfl-wallet -n openshift-gitops -o jsonpath='{.status.conditions[*].message}'
kubectl get placementdecision -n openshift-gitops -l cluster.open-cluster-management.io/placement=nfl-wallet-gitops-placement -o wide
```

**If the forbidden error persists** even when `auth can-i` returns **yes** and the pod is new: OpenShift GitOps may be using its own ClusterRole for the controller. Try **adding the permission to the ClusterRole the controller already uses** instead of relying only on our binding:

```bash
# See which ClusterRoles are bound to the controller SA (look for the line containing applicationset-controller)
kubectl get clusterrolebinding -o jsonpath='{range .items[*]}{.metadata.name}{"\t"}{.roleRef.name}{"\t"}{.subjects[*].name}{"\n"}{end}' | findstr applicationset
```

If an operator ClusterRole appears (e.g. `openshift-gitops-applicationset-controller` or `argocd-applicationset-controller`), add the placementdecisions rule to it:

```bash
# Replace CLUSTERROLE_NAME with the name from the previous command
kubectl patch clusterrole CLUSTERROLE_NAME --type='json' -p='[{"op": "add", "path": "/rules/-", "value": {"apiGroups": ["cluster.open-cluster-management.io"], "resources": ["placementdecisions"], "verbs": ["get", "list", "watch"]}}]'
```

Then delete the controller pod so it picks up the new permissions:  
`kubectl delete pod -n openshift-gitops -l app.kubernetes.io/name=applicationset-controller`  
(or by pod name if that label does not exist).

**"The server could not find the requested resource"** (no longer "forbidden"): RBAC is fine; the controller cannot find the resource. Verify: (1) you are on the **HUB** (`kubectl get placementdecision -n openshift-gitops` should list resources), (2) the ConfigMap `acm-placement` has the correct `apiVersion` and `kind`. Then force a refresh of the ApplicationSet:

```bash
kubectl annotate applicationset nfl-wallet -n openshift-gitops argocd.argoproj.io/refresh=hard --overwrite
# Wait ~1 minute and check
kubectl get applicationset nfl-wallet -n openshift-gitops -o jsonpath='{.status.conditions[*].message}'
kubectl get applications -n openshift-gitops
```

If it still fails, check the controller logs: `kubectl logs -n openshift-gitops deployment/openshift-gitops-applicationset-controller --tail=100`

**Workaround:** If clusterDecisionResource fails with "could not find the requested resource", verify that the PlacementDecision exists and has the correct label. As a temporary alternative, apply `app-nfl-wallet-east.yaml` and `app-nfl-wallet-west.yaml` to get 3 apps per cluster (edit `server` in west for the west cluster). This does not generate the 6 apps with names dev-east, dev-west, etc., but allows deployment to both clusters.

If step 2 prints **no**, the RoleBinding may point to the wrong ServiceAccount. Get the actual SA used by the controller:

```bash
kubectl get deployment -n openshift-gitops -o jsonpath='{range .items[*]}{.metadata.name}{"\t"}{.spec.template.spec.serviceAccountName}{"\n"}{end}'
```

If the SA name is different from `openshift-gitops-applicationset-controller`, edit `argocd-applicationset-rbac-placement.yaml` and set `subjects[0].name` to that value, then re-apply.

## ComparisonError: failed to discover server resources for gateway.networking.k8s.io/v1beta1: Unauthorized

This happens when Argo CD compares desired vs live state on the **destination (managed) cluster** (e.g. east or west). The token in the cluster secret does not have permission to list/discover the Gateway API on that cluster.

**Fix (on each managed cluster where the app is deployed):**

1. **Apply RBAC on the managed cluster** so the identity Argo CD uses has full access (including Gateway API). From this repo:
   ```bash
   # Log in to the MANAGED cluster (east or west), not the hub
   oc login https://api.<managed-cluster-domain>:6443
   oc apply -f docs/managed-cluster-argocd-rbac.yaml
   ```
   That manifest grants **cluster-admin** to `system:serviceaccount:openshift-gitops:openshift-gitops-argocd-application-controller` on the managed cluster. If the namespace or ServiceAccount does not exist there yet, create the namespace first: `oc create namespace openshift-gitops`. With ACM/GitOpsCluster, the SA may be created when the cluster is registered for GitOps.

2. **Ensure the hub’s cluster secret uses that token.** The cluster secret in `openshift-gitops` (e.g. for destination `east`) must contain a bearer token for an identity that has those permissions on the managed cluster. If you use ACM-managed cluster secrets, the token should be for the same SA. If you created the secret manually, get a token for that SA on the managed cluster and update the secret on the hub (see `docs/argocd-cluster-secrets-manual.yaml`).

3. **Restart the application controller** on the hub so it picks up the token:
   ```bash
   kubectl rollout restart statefulset/openshift-gitops-application-controller -n openshift-gitops
   ```
   Then sync the Application again.

**Verify on the managed cluster** (after step 1) that the SA can list Gateway API resources:

```bash
oc auth can-i list gateways.gateway.networking.k8s.io --as=system:serviceaccount:openshift-gitops:openshift-gitops-argocd-application-controller -n openshift-gitops
# Should print "yes"
```

If the hub uses a different ServiceAccount name for the application controller, use that in the ClusterRoleBinding and in the `--as` check. See `docs/getting-started.md` and `docs/managed-cluster-argocd-rbac.yaml`.

## East not deploying / only west has apps

The ApplicationSet uses a **matrix** generator (clusterDecisionResource × list). It does not favor one cluster over another. If west deploys but east does not:

1. **Check that all 6 Applications exist** on the hub:
   ```bash
   kubectl get applications.argoproj.io -n openshift-gitops -o custom-columns=NAME:.metadata.name,DESTINATION:.spec.destination.name,SYNC:.status.sync.status
   ```
   You should see: dev-east, dev-west, test-east, test-west, prod-east, prod-west. If the 3 **east** apps are missing, the ApplicationSet may not have created them or they were deleted.

2. **Force the ApplicationSet to reconcile** (recreate missing apps):
   ```bash
   kubectl annotate applicationset nfl-wallet -n openshift-gitops argocd.argoproj.io/refresh=hard --overwrite
   kubectl rollout restart deployment/openshift-gitops-applicationset-controller -n openshift-gitops
   ```
   Wait ~30s and run the `kubectl get applications.argoproj.io` again.

3. **Cluster name must match** — Argo CD resolves `destination.name: east` using the cluster secret whose `data.name` is `east`. The secret `cluster-east` must have `name: east` (and the correct server URL). Verify: `./scripts/verify-cluster-secrets.sh --test-api`. If east returns HTTP 200, the secret is valid.

4. **ManagedCluster names on the hub** — If you use GitOpsCluster, it often creates cluster secrets using the **ManagedCluster** resource name. So if your east cluster is registered as a ManagedCluster named `east`, the secret created by GitOpsCluster will have `name: east`. If the ManagedCluster is named differently (e.g. `cluster-s6krm`), you must still have a cluster secret that Argo CD sees as name **east** (e.g. manual `cluster-east` with `data.name: east`). Verify: `kubectl get secret -n openshift-gitops -l argocd.argoproj.io/secret-type=cluster -o custom-columns=NAME:.metadata.name,CLUSTER:.data.name`

## Other problems in a broken spec

- **Wrong template name** — With goTemplate use `{{.appName}}-{{.namespace}}-{{.clusterName}}`; not `nfl-wallet-{{name}}` (matrix generators do not provide `name`).
- **Placement label** — In `clusterDecisionResource.labelSelector.matchLabels`, `cluster.open-cluster-management.io/placement` must match your Placement name (e.g. `nfl-wallet-placement` or `nfl-wallet-gitops-placement`). Edit the value in `app-nfl-wallet-acm-cluster-decision.yaml` if needed.
- **Annotation** — You can omit `kubectl.kubernetes.io/last-applied-configuration`; manage the ApplicationSet from Git when possible.

## Missing ConfigMap

The ApplicationSet uses Kustomize, not Helm. Helm value files or ConfigMaps are not required.
