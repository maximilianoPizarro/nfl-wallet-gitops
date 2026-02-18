#!/usr/bin/env bash
# Force refresh and sync for all 6 NFL Wallet Applications (hub).
# Run with kubectl context pointing to the HUB cluster.
#
# Usage: ./scripts/force-sync-apps.sh

set -e
NS="openshift-gitops"
APPS=(
  nfl-wallet-nfl-wallet-dev-east
  nfl-wallet-nfl-wallet-dev-west
  nfl-wallet-nfl-wallet-test-east
  nfl-wallet-nfl-wallet-test-west
  nfl-wallet-nfl-wallet-prod-east
  nfl-wallet-nfl-wallet-prod-west
)

echo "Hard refresh (invalidate caches and re-evaluate state)..."
for app in "${APPS[@]}"; do
  kubectl annotate application "$app" -n "$NS" argocd.argoproj.io/refresh=hard --overwrite 2>/dev/null || true
done

echo ""
echo "With automated syncPolicy, OutOfSync apps should sync shortly. Progressing -> Healthy once workloads are ready."
echo ""
echo "Current status:"
kubectl get applications -n "$NS" -o custom-columns=NAME:.metadata.name,SYNC:.status.sync.status,HEALTH:.status.health.status
