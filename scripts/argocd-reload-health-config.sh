#!/usr/bin/env bash
# Apply argocd-cm health customizations and restart Argo CD so apps stop showing Progressing.
# Run from repo root with kubectl context = hub (openshift-gitops namespace).

set -e
SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
REPO_ROOT="$(cd "$SCRIPT_DIR/.." && pwd)"
PATCH_FILE="$REPO_ROOT/docs/argocd-cm-health-customizations.yaml"

if [ ! -f "$PATCH_FILE" ]; then
  echo "Patch file not found: $PATCH_FILE"
  exit 1
fi

echo "Patching argocd-cm in openshift-gitops..."
kubectl patch configmap argocd-cm -n openshift-gitops --type merge --patch-file "$PATCH_FILE"

echo "Restarting Argo CD server..."
kubectl rollout restart deployment/openshift-gitops-server -n openshift-gitops

echo "Restarting application controller (StatefulSet or Deployment)..."
if kubectl get statefulset argocd-application-controller -n openshift-gitops &>/dev/null; then
  kubectl rollout restart statefulset/argocd-application-controller -n openshift-gitops
elif kubectl get deployment argocd-application-controller -n openshift-gitops &>/dev/null; then
  kubectl rollout restart deployment/argocd-application-controller -n openshift-gitops
else
  echo "No argocd-application-controller found; list workloads:"
  kubectl get deploy,statefulset -n openshift-gitops
fi

echo "Done. Wait ~30s then check app health in the Argo CD UI."
