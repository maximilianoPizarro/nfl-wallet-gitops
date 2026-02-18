#!/usr/bin/env bash
# Restart klusterlet on east2 and west2 so the registration agent updates the lease again
# (fixes AVAILABLE=Unknown / ManagedClusterLeaseUpdateStopped on the hub).
# Run from repo root; kubeconfig must have contexts for both clusters.

set -e
EAST_CTX="default/api-cluster-s6krm-s6krm-sandbox3480-opentlc-com:6443/kube:admin"
WEST_CTX="default/api-cluster-9nvg4-dynamic-redhatworkshops-io:6443/admin"

echo "Restarting klusterlet on east2..."
kubectl rollout restart deployment/klusterlet-agent deployment/klusterlet -n open-cluster-management-agent --context="$EAST_CTX"

echo "Restarting klusterlet on west2..."
kubectl rollout restart deployment/klusterlet-agent deployment/klusterlet -n open-cluster-management-agent --context="$WEST_CTX"

echo "Done. Wait 1–2 minutes, then on the hub run: kubectl get managedcluster east2 west2"
echo "AVAILABLE should change from Unknown to True."
