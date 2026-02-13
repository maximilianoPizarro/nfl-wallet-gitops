# Update Helm dependencies for all nfl-wallet env folders.
# Run from repo root. Commit charts/ and Chart.lock after running.
$ErrorActionPreference = "Stop"
helm repo add nfl-wallet https://maximilianopizarro.github.io/NFL-Wallet 2>$null
helm repo update
foreach ($dir in "nfl-wallet-dev", "nfl-wallet-test", "nfl-wallet-prod") {
    Push-Location $dir
    helm dependency update
    Pop-Location
}
Write-Host "Done. Commit charts/ and Chart.lock in each env folder."
