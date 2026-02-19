#!/usr/bin/env bash
# Label NFL Wallet namespaces for Istio sidecar injection so Kiali/Jaeger show
# workloads and traces. Run once per cluster (or after namespace creation).
# See docs/observability.md §6.3.
#
# Usage: ./scripts/label-istio-injection.sh [--restart]
#   --restart  Also rollout restart all deployments in those namespaces so
#              new pods get the sidecar (otherwise only new pods will have it).

set -e
RESTART=false
for arg in "$@"; do
  [ "$arg" = "--restart" ] && RESTART=true
done

NAMESPACES="nfl-wallet-dev nfl-wallet-test nfl-wallet-prod"

echo "Labeling namespaces for Istio injection..."
for ns in $NAMESPACES; do
  if kubectl get namespace "$ns" &>/dev/null; then
    kubectl label namespace "$ns" istio-injection=enabled --overwrite
    echo "  $ns: labeled"
  else
    echo "  $ns: not found (skip)"
  fi
done

if [ "$RESTART" = true ]; then
  echo "Restarting deployments so new pods get the sidecar..."
  for ns in $NAMESPACES; do
    if kubectl get namespace "$ns" &>/dev/null; then
      if kubectl get deployment -n "$ns" -o name 2>/dev/null | grep -q .; then
        kubectl rollout restart deployment -n "$ns" --all
        echo "  $ns: deployments restarted"
      fi
    fi
  done
  echo "Wait for pods to be 2/2 (app + istio-proxy), then check Kiali/Jaeger."
else
  echo "Tip: run with --restart to restart deployments and get sidecars on existing pods."
fi
