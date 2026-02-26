#!/usr/bin/env bash
# Refresh Argo CD cluster secret (east or west): create token on managed cluster, then update secret on hub.
#
# STEP 1 — On the MANAGED cluster (east or west): run with only cluster name.
#   oc login https://api.cluster-h625z.h625z.sandbox613.opentlc.com:6443   # for east
#   ./scripts/refresh-cluster-secret.sh east
#   Copy the token printed at the end.
#
# STEP 2 — On the HUB: run with cluster name and the token.
#   kubectl config use-context <hub>
#   ./scripts/refresh-cluster-secret.sh east "<PASTE_TOKEN_HERE>"
#
# Repeat for west (oc login to west, then ./scripts/refresh-cluster-secret.sh west, then on hub with token).
#
# Usage:
#   $0 east              → on managed cluster east: create SA, RBAC, token; print token
#   $0 west              → on managed cluster west: same
#   $0 east "<token>"    → on hub: update cluster-east secret and restart controller
#   $0 east @file       → on hub: read token from file (avoids shell truncation of long tokens)
#
# If the token is truncated when pasting, use a file: ./scripts/refresh-cluster-secret.sh east @east_token.txt

set -e
if [ $# -lt 1 ]; then
  echo "Usage: $0 <east|west> [TOKEN_OR_FILE]"
  echo "  On managed cluster: $0 east   (or west) — creates token, print it"
  echo "  On hub:            $0 east \"<token>\"   — updates secret and restarts controller"
  echo "  On hub (from file): $0 east @east_token.txt   — read token from file (no truncation)"
  exit 1
fi
CLUSTER="$1"
TOKEN="${2:-}"
# If second arg is @path, read token from file (avoids shell truncation)
if [ -n "$TOKEN" ] && [ "${TOKEN#@}" != "$TOKEN" ]; then
  TOKEN_FILE="${TOKEN#@}"
  if [ ! -f "$TOKEN_FILE" ]; then
    echo "Error: file not found: $TOKEN_FILE"
    exit 1
  fi
  TOKEN=$(tr -d '\n\r' < "$TOKEN_FILE")
  echo "Read token from $TOKEN_FILE ($(echo -n "$TOKEN" | wc -c) chars, newlines stripped)"
fi
NS="openshift-gitops"
SA="openshift-gitops-argocd-application-controller"
SECRET_NAME="cluster-${CLUSTER}"

# --- On hub: create or update secret and restart ---
if [ -n "$TOKEN" ]; then
  CONFIG_JSON="{\"tlsClientConfig\":{\"insecure\":true},\"bearerToken\":\"${TOKEN}\"}"
  if kubectl get secret "$SECRET_NAME" -n "$NS" &>/dev/null; then
    echo "Updating secret $SECRET_NAME on hub..."
    if echo -n "x" | base64 -w0 &>/dev/null; then
      CONFIG_B64=$(echo -n "$CONFIG_JSON" | base64 -w0)
    else
      CONFIG_B64=$(echo -n "$CONFIG_JSON" | base64)
    fi
    kubectl patch secret "$SECRET_NAME" -n "$NS" --type=json -p='[{"op":"replace","path":"/data/config","value":"'"$CONFIG_B64"'"}]'
  else
    echo "Creating secret $SECRET_NAME on hub (was missing)..."
    case "$CLUSTER" in
      east) SERVER_URL="https://api.cluster-h625z.h625z.sandbox613.opentlc.com:6443" ;;
      west) SERVER_URL="https://api.cluster-2l9nd.dynamic.redhatworkshops.io:6443" ;;
      *)    echo "Unknown cluster: $CLUSTER"; exit 1 ;;
    esac
    kubectl create secret generic "$SECRET_NAME" -n "$NS" \
      --from-literal=name="$CLUSTER" \
      --from-literal=server="$SERVER_URL" \
      --from-literal=config="$CONFIG_JSON" \
      --type=Opaque
    kubectl label secret "$SECRET_NAME" -n "$NS" argocd.argoproj.io/secret-type=cluster
  fi
  echo "Restarting application controller and repo server..."
  kubectl rollout restart statefulset/openshift-gitops-application-controller -n "$NS"
  kubectl rollout restart deployment/openshift-gitops-repo-server -n "$NS" 2>/dev/null || true
  echo "Done. Wait ~1 min then run: ./scripts/verify-cluster-secrets.sh --test-api"
  exit 0
fi

# --- On managed cluster: create namespace, SA, RBAC, token ---
echo "Preparing $CLUSTER for Argo CD (namespace, SA, RBAC, token)..."
oc create namespace "$NS" --dry-run=client -o yaml | oc apply -f -
oc create serviceaccount "$SA" -n "$NS" --dry-run=client -o yaml | oc apply -f -

# Apply RBAC (inline so it works without repo path)
oc apply -f - <<'RBAC'
apiVersion: rbac.authorization.k8s.io/v1
kind: ClusterRoleBinding
metadata:
  name: argocd-application-controller-admin
roleRef:
  apiGroup: rbac.authorization.k8s.io
  kind: ClusterRole
  name: cluster-admin
subjects:
  - kind: ServiceAccount
    name: openshift-gitops-argocd-application-controller
    namespace: openshift-gitops
RBAC

echo "Creating token (30 days)..."
NEW_TOKEN=$(oc create token "$SA" -n "$NS" --duration=720h)
echo ""
echo "=============================================="
echo "Copy the token below and run on the HUB:"
echo ""
echo "  ./scripts/refresh-cluster-secret.sh $CLUSTER \"\$TOKEN\""
echo ""
echo "(paste the token between quotes in the command above)"
echo "=============================================="
echo "$NEW_TOKEN"
echo "=============================================="
