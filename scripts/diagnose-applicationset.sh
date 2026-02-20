#!/usr/bin/env bash
# Diagnose ApplicationSet and cluster registration (run on HUB).
# Use when east is not deploying but west is, or when apps are missing.
#
# Usage: ./scripts/diagnose-applicationset.sh

set -e
NS="openshift-gitops"
echo "=== 1. ApplicationSet status ==="
kubectl get applicationset nfl-wallet -n "$NS" -o wide 2>/dev/null || { echo "ApplicationSet nfl-wallet not found"; exit 1; }
echo ""
echo "=== 2. Expected: 6 Applications (dev/test/prod x east/west) ==="
kubectl get applications.argoproj.io -n "$NS" -l app.kubernetes.io/part-of=application-lifecycle -o custom-columns=NAME:.metadata.name,DESTINATION:.spec.destination.name,SYNC:.status.sync.status,HEALTH:.status.health.status 2>/dev/null || kubectl get applications -n "$NS" -o custom-columns=NAME:.metadata.name,DESTINATION:.spec.destination.name,SYNC:.status.sync.status,HEALTH:.status.health.status 2>/dev/null
APP_COUNT=$(kubectl get applications.argoproj.io -n "$NS" -l app.kubernetes.io/part-of=application-lifecycle --no-headers 2>/dev/null | wc -l || kubectl get applications -n "$NS" --no-headers 2>/dev/null | wc -l)
echo ""
echo "Total Applications: $APP_COUNT (expected 6)"
echo ""
echo "=== 3. Cluster secrets (Argo CD must have cluster 'east' and 'west') ==="
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
echo "=== 4. ManagedClusters (ACM) — names should match destination: east / west ==="
kubectl get managedcluster -o custom-columns=NAME:.metadata.name,AVAILABLE:.status.conditions[0].reason 2>/dev/null || echo "ManagedCluster CRD not found (ACM not installed or different namespace)."
echo ""
echo "=== 5. If east apps are missing or SyncFailed ==="
echo "  - Ensure ManagedCluster for east is named 'east' (or cluster secret data.name is 'east')."
echo "  - Ensure cluster-east secret exists and token works: ./scripts/verify-cluster-secrets.sh --test-api"
echo "  - Hard refresh ApplicationSet: kubectl annotate applicationset nfl-wallet -n $NS argocd.argoproj.io/refresh=hard --overwrite"
echo "  - Restart ApplicationSet controller: kubectl rollout restart deployment/openshift-gitops-applicationset-controller -n $NS"
