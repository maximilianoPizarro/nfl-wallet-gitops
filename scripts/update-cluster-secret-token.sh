#!/usr/bin/env bash
# Update the Argo CD cluster secret (east or west) with a new bearer token.
# Run with kubectl context = HUB. Get token from the managed cluster: oc whoami -t
#
# Usage: ./scripts/update-cluster-secret-token.sh <east|west> <TOKEN>

set -e
if [ $# -ne 2 ]; then
  echo "Usage: $0 <east|west> <TOKEN>"
  echo "Example: $0 east \"\$(oc whoami -t)\""
  exit 1
fi
CLUSTER="$1"
TOKEN="$2"
SECRET_NAME="cluster-${CLUSTER}"
NS="openshift-gitops"

CONFIG_JSON="{\"tlsClientConfig\":{\"insecure\":true},\"bearerToken\":\"${TOKEN}\"}"
CONFIG_B64=$(echo -n "$CONFIG_JSON" | base64 -w0)
kubectl patch secret "$SECRET_NAME" -n "$NS" --type=json -p='[{"op":"replace","path":"/data/config","value":"'"$CONFIG_B64"'"}]'
echo "Updated secret $SECRET_NAME. Restarting application controller..."
kubectl rollout restart statefulset/openshift-gitops-application-controller -n "$NS"
echo "Done. Wait ~30s then sync the apps again."
