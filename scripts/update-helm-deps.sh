#!/usr/bin/env bash
# Update Helm dependencies for all nfl-wallet env folders.
# Run from repo root. Commit charts/ and Chart.lock after running.
set -e
helm repo add nfl-wallet https://maximilianopizarro.github.io/NFL-Wallet
helm repo update
for dir in nfl-wallet-dev nfl-wallet-test nfl-wallet-prod; do
  (cd "$dir" && helm dependency update)
done
echo "Done. Commit charts/ and Chart.lock in each env folder."
