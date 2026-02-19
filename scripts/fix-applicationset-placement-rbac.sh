#!/usr/bin/env bash
# ---------------------------------------------------------------------------
# Fix RBAC so ApplicationSet controller can list PlacementDecision (run on HUB)
# ---------------------------------------------------------------------------
# Usage: ./scripts/fix-applicationset-placement-rbac.sh
# Or:    bash scripts/fix-applicationset-placement-rbac.sh
#
# This script:
#   1. Discovers the exact PlacementDecision resource name on your cluster
#   2. Removes any old RoleBinding
#   3. Creates ClusterRole + ClusterRoleBinding for that resource
#   4. Restarts the ApplicationSet controller
#   5. Verifies with kubectl auth can-i
# ---------------------------------------------------------------------------
set -e

NAMESPACE="${NAMESPACE:-openshift-gitops}"
SA_NAME="${SA_NAME:-openshift-gitops-applicationset-controller}"
CLUSTER_ROLE_NAME="ocm-placement-consumer-openshift-gitops"
CLUSTER_ROLE_BINDING_NAME="ocm-placement-consumer-applicationset-openshift-gitops"
API_GROUP="cluster.open-cluster-management.io"

echo "=== 1. Discovering PlacementDecision resource name on this cluster ==="
RESOURCE_NAME=$(kubectl api-resources --api-group="$API_GROUP" -o jsonpath='{range .resources[?(@.kind=="PlacementDecision")]}{.name}{"\n"}{end}' 2>/dev/null | head -1)
if [ -z "$RESOURCE_NAME" ]; then
  echo "WARNING: PlacementDecision not found in api-resources for $API_GROUP. Using fallback: placementdecisions"
  RESOURCE_NAME="placementdecisions"
else
  echo "Found resource name: $RESOURCE_NAME"
fi

echo ""
echo "=== 2. Removing old RoleBinding (if any) ==="
kubectl delete rolebinding ocm-placement-consumer-applicationset -n "$NAMESPACE" --ignore-not-found || true

echo ""
echo "=== 3. Creating ClusterRole and ClusterRoleBinding ==="
kubectl apply -f - <<EOF
apiVersion: rbac.authorization.k8s.io/v1
kind: ClusterRole
metadata:
  name: $CLUSTER_ROLE_NAME
rules:
  - apiGroups: ["$API_GROUP"]
    resources: ["$RESOURCE_NAME"]
    verbs: ["get", "list", "watch"]
---
apiVersion: rbac.authorization.k8s.io/v1
kind: ClusterRoleBinding
metadata:
  name: $CLUSTER_ROLE_BINDING_NAME
roleRef:
  apiGroup: rbac.authorization.k8s.io
  kind: ClusterRole
  name: $CLUSTER_ROLE_NAME
subjects:
  - kind: ServiceAccount
    namespace: $NAMESPACE
    name: $SA_NAME
EOF

echo ""
echo "=== 4. Restarting ApplicationSet controller ==="
# Find deployment that uses our ServiceAccount (OpenShift GitOps may not use the applicationset-controller label)
DEPLOY=$(kubectl get deployment -n "$NAMESPACE" -o jsonpath="{range .items[?(@.spec.template.spec.serviceAccountName=='$SA_NAME')]}{.metadata.name}{'\n'}{end}" 2>/dev/null | head -1)
if [ -z "$DEPLOY" ]; then
  DEPLOY=$(kubectl get deployment -n "$NAMESPACE" -l app.kubernetes.io/name=applicationset-controller -o jsonpath='{.items[0].metadata.name}' 2>/dev/null || true)
fi
if [ -n "$DEPLOY" ]; then
  echo "Restarting deployment: $DEPLOY"
  kubectl rollout restart deployment "$DEPLOY" -n "$NAMESPACE"
  echo "Waiting for rollout..."
  kubectl rollout status deployment "$DEPLOY" -n "$NAMESPACE" --timeout=120s
else
  echo "No deployment found using ServiceAccount $SA_NAME. List deployments and their SAs:"
  kubectl get deployment -n "$NAMESPACE" -o jsonpath='{range .items[*]}{.metadata.name}{"\t"}{.spec.template.spec.serviceAccountName}{"\n"}{end}'
  echo "Restart the deployment that uses $SA_NAME manually."
fi

echo ""
echo "=== 5. Verifying permission ==="
CAN_I=$(kubectl auth can-i list "$RESOURCE_NAME.$API_GROUP" -n "$NAMESPACE" --as="system:serviceaccount:$NAMESPACE:$SA_NAME" 2>/dev/null || echo "no")
if [ "$CAN_I" = "yes" ]; then
  echo "SUCCESS: ServiceAccount $SA_NAME can list $RESOURCE_NAME in $NAMESPACE."
else
  echo "WARNING: auth can-i returned: $CAN_I"
  echo "Check that the deployment uses this ServiceAccount:"
  kubectl get deployment -n "$NAMESPACE" -o jsonpath='{range .items[*]}{.metadata.name}{"\t"}{.spec.template.spec.serviceAccountName}{"\n"}{end}'
  echo ""
  echo "If the SA name differs, set SA_NAME and re-run: SA_NAME=actual-sa-name $0"
fi

echo ""
echo "Done. Wait ~1 minute then check: kubectl get applicationset nfl-wallet -n $NAMESPACE -o jsonpath='{.status.conditions[*].message}'"
