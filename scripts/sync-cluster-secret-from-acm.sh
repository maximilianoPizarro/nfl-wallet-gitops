#!/usr/bin/env bash
# On the HUB: try to copy credentials from ACM's managed-cluster import secret into Argo CD's cluster secret.
# Use this when the token you created on the managed cluster still returns 401 (e.g. west).
#
# ACM may store a kubeconfig in open-cluster-management-agent: <cluster>-import (key import-config).
# This script extracts server + token from that kubeconfig and updates openshift-gitops cluster-<name>.
#
# Usage (run on HUB): ./scripts/sync-cluster-secret-from-acm.sh west
#                     ./scripts/sync-cluster-secret-from-acm.sh east

set -e
if [ $# -ne 1 ]; then
  echo "Usage: $0 <east|west>"
  echo "Run on the HUB. Tries to copy token from ACM import secret to Argo CD cluster secret."
  exit 1
fi
CLUSTER="$1"
NS_GITOPS="openshift-gitops"
NS_ACM="open-cluster-management-agent"
SECRET_ACM="${CLUSTER}-import"
SECRET_ARGOCD="cluster-${CLUSTER}"

# Default server URLs if not found in kubeconfig
case "$CLUSTER" in
  east) DEFAULT_SERVER="https://api.cluster-h625z.h625z.sandbox613.opentlc.com:6443" ;;
  west) DEFAULT_SERVER="https://api.cluster-2l9nd.dynamic.redhatworkshops.io:6443" ;;
  *)    echo "Unknown cluster: $CLUSTER"; exit 1 ;;
esac

echo "Looking for ACM import secret: $SECRET_ACM in $NS_ACM..."
for NS in "$NS_ACM" open-cluster-management-agent-addon open-cluster-management; do
  if kubectl get secret "$SECRET_ACM" -n "$NS" &>/dev/null; then
    NS_ACM="$NS"
    break
  fi
done
if ! kubectl get secret "$SECRET_ACM" -n "$NS_ACM" &>/dev/null; then
  echo "Secret $SECRET_ACM not found in $NS_ACM (or addon/ocm namespaces). Cannot sync from ACM."
  echo "List secrets: kubectl get secret -n open-cluster-management-agent | grep -E 'west|import'"
  echo "Then create the token on the managed cluster: oc login ... ; ./scripts/refresh-cluster-secret.sh $CLUSTER"
  exit 1
fi
echo "Using secret in namespace: $NS_ACM"

# Try import-config (kubeconfig)
RAW=$(kubectl get secret "$SECRET_ACM" -n "$NS_ACM" -o jsonpath='{.data.import-config}' 2>/dev/null | base64 -d 2>/dev/null || true)
if [ -z "$RAW" ]; then
  RAW=$(kubectl get secret "$SECRET_ACM" -n "$NS_ACM" -o jsonpath='{.data.kubeconfig}' 2>/dev/null | base64 -d 2>/dev/null || true)
fi
if [ -z "$RAW" ]; then
  echo "Could not extract kubeconfig from $SECRET_ACM (no import-config or kubeconfig key)."
  exit 1
fi

# Extract server URL (cluster.server)
SERVER=$(echo "$RAW" | grep -E 'server:.*https' | head -1 | sed 's/.*server:[[:space:]]*//' | tr -d '\r')
[ -z "$SERVER" ] && SERVER="$DEFAULT_SERVER"

# Extract token (user.token) — kubeconfig has "token: eyJ..."
TOKEN=$(echo "$RAW" | awk '/^[[:space:]]*token:[[:space:]]/{print $2; exit}' | tr -d '\r')
if [ -z "$TOKEN" ]; then
  TOKEN=$(echo "$RAW" | sed -n 's/.*token:[[:space:]]*\([^[:space:]]*\).*/\1/p' | head -1 | tr -d '\r')
fi
if [ -z "$TOKEN" ]; then
  echo "Could not extract token from kubeconfig."
  exit 1
fi

echo "Extracted server: $SERVER"
echo "Extracted token:  ${#TOKEN} chars"
echo "Updating Argo CD secret $SECRET_ARGOCD..."

CONFIG_JSON="{\"tlsClientConfig\":{\"insecure\":true},\"bearerToken\":\"${TOKEN}\"}"
if kubectl get secret "$SECRET_ARGOCD" -n "$NS_GITOPS" &>/dev/null; then
  if echo -n "x" | base64 -w0 &>/dev/null; then
    CONFIG_B64=$(echo -n "$CONFIG_JSON" | base64 -w0)
  else
    CONFIG_B64=$(echo -n "$CONFIG_JSON" | base64)
  fi
  kubectl patch secret "$SECRET_ARGOCD" -n "$NS_GITOPS" --type=json -p='[{"op":"replace","path":"/data/config","value":"'"$CONFIG_B64"'"}]'
  kubectl patch secret "$SECRET_ARGOCD" -n "$NS_GITOPS" --type=merge -p="{\"stringData\":{\"server\":\"$SERVER\"}}" 2>/dev/null || true
else
  kubectl create secret generic "$SECRET_ARGOCD" -n "$NS_GITOPS" \
    --from-literal=name="$CLUSTER" \
    --from-literal=server="$SERVER" \
    --from-literal=config="$CONFIG_JSON" \
    --type=Opaque
  kubectl label secret "$SECRET_ARGOCD" -n "$NS_GITOPS" argocd.argoproj.io/secret-type=cluster
fi

echo "Restarting application controller..."
kubectl rollout restart statefulset/openshift-gitops-application-controller -n "$NS_GITOPS"
kubectl rollout restart deployment/openshift-gitops-repo-server -n "$NS_GITOPS" 2>/dev/null || true
echo "Done. Run: ./scripts/verify-cluster-secrets.sh --test-api"
