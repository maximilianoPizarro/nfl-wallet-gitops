#!/usr/bin/env bash
# Diagnose ApplicationSet and cluster registration (run on HUB).
# Use when no applications are created, or east/west apps are missing.
#
# Usage: ./scripts/diagnose-applicationset.sh

set -e
NS="openshift-gitops"
echo "=== 1. ApplicationSet status ==="
kubectl get applicationset nfl-wallet -n "$NS" -o wide 2>/dev/null || { echo "ApplicationSet nfl-wallet not found"; exit 1; }
echo ""
echo "=== 2. PlacementDecision (MUST have decisions for apps to be created) ==="
PD=$(kubectl get placementdecision -n "$NS" -l cluster.open-cluster-management.io/placement=nfl-wallet-gitops-placement -o name 2>/dev/null | head -1)
if [[ -n "$PD" ]]; then
  kubectl get "$PD" -n "$NS" -o wide 2>/dev/null || true
  CLUSTERS=$(kubectl get "$PD" -n "$NS" -o jsonpath='{.status.decisions[*].clusterName}' 2>/dev/null)
  echo "  Cluster names in decisions: ${CLUSTERS:-<EMPTY - add region=east/west to ManagedClusters>}"
else
  echo "  PlacementDecision NOT FOUND. Ensure app-nfl-wallet-acm.yaml was applied and Placement selects clusters."
fi
echo ""
echo "=== 3. Expected: 6 Applications (dev/test/prod x east/west) ==="
kubectl get applications.argoproj.io -n "$NS" -l app.kubernetes.io/part-of=application-lifecycle -o custom-columns=NAME:.metadata.name,DESTINATION:.spec.destination.name,SYNC:.status.sync.status,HEALTH:.status.health.status 2>/dev/null || kubectl get applications -n "$NS" -o custom-columns=NAME:.metadata.name,DESTINATION:.spec.destination.name,SYNC:.status.sync.status,HEALTH:.status.health.status 2>/dev/null
APP_COUNT=$(kubectl get applications.argoproj.io -n "$NS" -l app.kubernetes.io/part-of=application-lifecycle --no-headers 2>/dev/null | wc -l || kubectl get applications -n "$NS" --no-headers 2>/dev/null | wc -l)
echo ""
echo "Total Applications: $APP_COUNT (expected 6)"
echo ""
echo "=== 4. Cluster secrets (Argo CD must have cluster 'east' and 'west') ==="
kubectl get secret -n "$NS" -l argocd.argoproj.io/secret-type=cluster -o custom-columns=NAME:.metadata.name,CLUSTER_NAME:.data.name,SERVER:.data.server 2>/dev/null
for s in cluster-east cluster-west; do
  if kubectl get secret "$s" -n "$NS" &>/dev/null; then
    CNAME=$(kubectl get secret "$s" -n "$NS" -o jsonpath='{.data.name}' 2>/dev/null | base64 -d 2>/dev/null || echo "?")
    echo "  $s -> cluster name in secret: $CNAME"
  else
    echo "  $s -> MISSING"
  fi
done
echo ""
echo "=== 5. ManagedClusters (ACM) — must have region=east or region=west label ==="
kubectl get managedcluster -o custom-columns=NAME:.metadata.name,AVAILABLE:.status.conditions[0].reason,REGION:.metadata.labels.region 2>/dev/null || echo "ManagedCluster CRD not found (ACM not installed or different namespace)."
echo ""
echo "=== 6. ManagedClusterSetBinding (global -> openshift-gitops) ==="
kubectl get managedclustersetbinding -n "$NS" 2>/dev/null || echo "ManagedClusterSetBinding not found."
echo ""
echo "=== 7. If no apps or SyncFailed ==="
echo "  - Ensure ManagedClusters have label region=east or region=west: kubectl label managedcluster east region=east"
echo "  - Ensure PlacementDecision has decisions (see step 2). If empty, add region labels to ManagedClusters."
echo "  - If apps exist but SyncFailed: ./scripts/verify-cluster-secrets.sh --test-api"
echo "  - Hard refresh: kubectl annotate applicationset nfl-wallet -n $NS argocd.argoproj.io/refresh=hard --overwrite"
echo "  - Restart controller: kubectl rollout restart deployment/openshift-gitops-applicationset-controller -n $NS"
