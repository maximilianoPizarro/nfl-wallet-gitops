# Force refresh for all 6 NFL Wallet Applications (hub). Run with kubectl context = HUB.
# Usage: .\scripts\force-sync-apps.ps1

$ErrorActionPreference = "Stop"
$NS = "openshift-gitops"
$APPS = @(
    "nfl-wallet-nfl-wallet-dev-east",
    "nfl-wallet-nfl-wallet-dev-west",
    "nfl-wallet-nfl-wallet-test-east",
    "nfl-wallet-nfl-wallet-test-west",
    "nfl-wallet-nfl-wallet-prod-east",
    "nfl-wallet-nfl-wallet-prod-west"
)

Write-Host "Hard refresh (invalidate caches and re-evaluate state)..."
foreach ($app in $APPS) {
    kubectl annotate application $app -n $NS argocd.argoproj.io/refresh=hard --overwrite 2>$null
}

Write-Host ""
Write-Host "With automated syncPolicy, OutOfSync apps should sync shortly. Progressing -> Healthy once workloads are ready."
Write-Host ""
Write-Host "Current status:"
kubectl get applications -n $NS -o custom-columns=NAME:.metadata.name,SYNC:.status.sync.status,HEALTH:.status.health.status
