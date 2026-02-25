# ApplicationSet nfl-wallet – fix for controller errors

If the ApplicationSet controller reports an error or **"Must have required property 'clusterDecisionResource'"**, use the steps below.

**Quick checklist:**
1. You must apply **`app-nfl-wallet-acm-cluster-decision.yaml`** (not `app-nfl-wallet-acm.yaml`).
2. After applying, the **first** generator in `spec.generators` must be `clusterDecisionResource` (verify with the command in the next section).
3. If the policy still fails, it may require **`spec.clusterDecisionResource`** (top-level). That does not exist in the ApplicationSet API; see the "If the error persists" paragraph below and share it with your admin.

## "Must have required property 'clusterDecisionResource'"

**Check first:** Are you applying the correct file? Use **`app-nfl-wallet-acm-cluster-decision.yaml`** (has `clusterDecisionResource`). If you apply **`app-nfl-wallet-acm.yaml`** (list only), the policy will fail.

**Force the correct structure:** If you already applied the list-only version or the order of generators changed, replace the ApplicationSet so the first generator is `clusterDecisionResource`:

```bash
kubectl delete applicationset nfl-wallet -n openshift-gitops
kubectl apply -f app-nfl-wallet-acm-cluster-decision.yaml -n openshift-gitops
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

**Fix:** Remove the entire `clusterDecisionResource` block from that generator and use only the `list` generator as in `app-nfl-wallet-acm.yaml`:

```bash
kubectl apply -f app-nfl-wallet-acm.yaml -n openshift-gitops
```

### 2. Policy requires a clusterDecisionResource generator

If your environment **requires** that the ApplicationSet use a `clusterDecisionResource` generator (e.g. ACM policy), use the variant that has it as a **separate** generator (matrix with list):

1. Apply **RBAC** so the ApplicationSet controller can list PlacementDecisions, then the ConfigMap and ApplicationSet:

```bash
kubectl apply -f argocd-applicationset-rbac-placement.yaml -n openshift-gitops
kubectl apply -f argocd-placement-configmap.yaml -n openshift-gitops
kubectl apply -f app-nfl-wallet-acm-cluster-decision.yaml -n openshift-gitops
```

The ConfigMap must be named `acm-placement` (`configMapRef: acm-placement`) and the `clusterDecisionResource` generator must include `requeueAfterSeconds`; otherwise policy validation fails. The **first** generator in the list must be `clusterDecisionResource` (with `configMapRef` and `requeueAfterSeconds`) so policy checks pass.

2. Ensure Placements and GitOpsCluster from `app-nfl-wallet-acm.yaml` are applied first so the PlacementDecision `nfl-wallet-gitops-placement-1` (or similar) exists and lists both east and west in `status.decisions`.

3. Use **either** `app-nfl-wallet-acm.yaml` (list only) **or** `app-nfl-wallet-acm-cluster-decision.yaml` (list + clusterDecisionResource), not both.

In the variant, `clusterDecisionResource` is its own generator; it is **not** in the same object as `list`. The matrix produces 6 Applications (dev/test/prod × east/west).

**If the error persists:** The policy may be checking for **`spec.clusterDecisionResource`** (a top-level key under `spec`). The Argo CD ApplicationSet API **does not support that**. The API only has:

- `spec.generators[]` — array of generator objects
- each generator object has **one** key: either `list`, or `clusterDecisionResource`, or `git`, etc.

So the valid structure is **`spec.generators[0].clusterDecisionResource`**, not `spec.clusterDecisionResource`. You cannot add a top-level `spec.clusterDecisionResource` because the CRD would reject it as an unknown field.

**What to ask your platform/ACM admin:** Update the policy so it validates that **at least one element of `spec.generators`** has the key `clusterDecisionResource`, instead of requiring `spec.clusterDecisionResource`. For example (Gatekeeper/Rego-style idea): *"require that `spec.generators` contains an item that has the key `clusterDecisionResource`"* (e.g. check `spec.generators[i].clusterDecisionResource` for some `i`). Alternatively, grant an exception for the `nfl-wallet` ApplicationSet in `openshift-gitops`.

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

**Practical workaround:** If you need the 6 Applications now and clusterDecisionResource still shows "could not find the requested resource", use the ApplicationSet that only uses the **list** generator (it does not depend on PlacementDecision). It creates the same 6 apps (dev/test/prod × east/west):

```bash
# Replace the ApplicationSet with the list-only variant
kubectl delete applicationset nfl-wallet -n openshift-gitops
kubectl apply -f app-nfl-wallet-acm.yaml -n openshift-gitops
```

After a few seconds: `kubectl get applications -n openshift-gitops`. If your policy requires clusterDecisionResource, you will need to debug with the controller logs or with the platform team.

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

The ApplicationSet uses a **list** generator with 6 elements (dev/test/prod × east/west). It does not prefer one cluster over the other. If west is deployed but east is not:

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

4. **ManagedCluster names on the hub** — If you use GitOpsCluster, it often creates cluster secrets using the **ManagedCluster** resource name. So if your east cluster is registered as a ManagedCluster named `east`, the secret created by GitOpsCluster will have `name: east`. If the ManagedCluster is named differently (e.g. `cluster-s6krm`), you must still have a cluster secret that Argo CD sees as name **east** (e.g. manual `cluster-east` with `data.name: east`). Verifica: `kubectl get secret -n openshift-gitops -l argocd.argoproj.io/secret-type=cluster -o custom-columns=NAME:.metadata.name,CLUSTER:.data.name`

## Other problems in a broken spec

- **Wrong template name** — With goTemplate use `{{.appName}}-{{.namespace}}-{{.clusterName}}`; not `nfl-wallet-{{name}}` (matrix generators do not provide `name`).
- **Placement label** — In `clusterDecisionResource.labelSelector.matchLabels`, `cluster.open-cluster-management.io/placement` must match your Placement name (e.g. `nfl-wallet-placement` or `nfl-wallet-gitops-placement`). Edit the value in `app-nfl-wallet-acm-cluster-decision.yaml` if needed.
- **Annotation** — You can omit `kubectl.kubernetes.io/last-applied-configuration`; manage the ApplicationSet from Git when possible.

## Missing ConfigMap

See the same doc (if present) or the ApplicationSet source for the "Missing ConfigMap" section. In short: use `ignoreMissingValueFiles: true` in `source.helm` (already in the repo), and ensure any ConfigMap the chart needs is created by the chart or by a template in this repo.
