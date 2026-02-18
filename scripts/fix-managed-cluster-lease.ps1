# Restart klusterlet on east2 and west2 so the registration agent updates the lease again
# (fixes AVAILABLE=Unknown / ManagedClusterLeaseUpdateStopped on the hub).
# Run from repo root; kubeconfig must have contexts for both clusters.

$ErrorActionPreference = "Stop"
$EastCtx = "default/api-cluster-s6krm-s6krm-sandbox3480-opentlc-com:6443/kube:admin"
$WestCtx = "default/api-cluster-9nvg4-dynamic-redhatworkshops-io:6443/admin"

Write-Host "Restarting klusterlet on east2..."
kubectl rollout restart deployment/klusterlet-agent deployment/klusterlet -n open-cluster-management-agent --context=$EastCtx

Write-Host "Restarting klusterlet on west2..."
kubectl rollout restart deployment/klusterlet-agent deployment/klusterlet -n open-cluster-management-agent --context=$WestCtx

Write-Host "Done. Wait 1–2 minutes, then on the hub run: kubectl get managedcluster east2 west2"
Write-Host "AVAILABLE should change from Unknown to True."
