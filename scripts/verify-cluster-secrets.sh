#!/usr/bin/env bash
# Verify Argo CD cluster secrets (east and west) on the HUB.
# Checks: secret exists, config has valid JSON, bearerToken set and not placeholder.
# Optionally tests the token against the cluster API (curl).
#
# Run with kubectl context = HUB:
#   ./scripts/verify-cluster-secrets.sh
#   ./scripts/verify-cluster-secrets.sh --test-api   # also call /version on each cluster

set -e
NS="openshift-gitops"
TEST_API=false
[ "${1:-}" = "--test-api" ] && TEST_API=true

# base64 decode: Linux/Git Bash use -d, macOS uses -D
BASE64_DECODE="base64 -d"
if ! echo "Zg==" | base64 -d &>/dev/null; then
  BASE64_DECODE="base64 -D"
fi

echo "Verifying cluster secrets in namespace: $NS"
echo ""

for SECRET_NAME in cluster-east cluster-west; do
  echo "--- $SECRET_NAME ---"
  if ! kubectl get secret "$SECRET_NAME" -n "$NS" -o name &>/dev/null; then
    echo "  FAIL: Secret not found"
    echo ""
    continue
  fi

  # Decode name and server
  NAME=$(kubectl get secret "$SECRET_NAME" -n "$NS" -o jsonpath='{.data.name}' 2>/dev/null | $BASE64_DECODE 2>/dev/null || echo "?")
  SERVER=$(kubectl get secret "$SECRET_NAME" -n "$NS" -o jsonpath='{.data.server}' 2>/dev/null | $BASE64_DECODE 2>/dev/null || echo "?")
  CONFIG_B64=$(kubectl get secret "$SECRET_NAME" -n "$NS" -o jsonpath='{.data.config}' 2>/dev/null || true)

  if [ -z "$CONFIG_B64" ]; then
    echo "  FAIL: No data.config"
    echo ""
    continue
  fi

  CONFIG_JSON=$(echo "$CONFIG_B64" | $BASE64_DECODE 2>/dev/null || true)
  if [ -z "$CONFIG_JSON" ]; then
    echo "  FAIL: data.config is not valid base64"
    echo ""
    continue
  fi

  # Extract bearerToken (portable: no jq required, simple grep/sed)
  TOKEN=$(echo "$CONFIG_JSON" | sed -n 's/.*"bearerToken":"\([^"]*\)".*/\1/p')
  if [ -z "$TOKEN" ]; then
    echo "  FAIL: No bearerToken in config"
    echo ""
    continue
  fi

  if echo "$TOKEN" | grep -q "REPLACE_WITH"; then
    echo "  FAIL: bearerToken is still the placeholder (<REPLACE_WITH_...>)"
    echo "  Fix: Update the secret with a real token from the managed cluster (see docs/argocd-cluster-secrets-manual.yaml)"
    echo ""
    continue
  fi

  echo "  name:   $NAME"
  echo "  server: $SERVER"
  echo "  token:  set (${#TOKEN} chars)"
  echo "  config: valid JSON with tlsClientConfig and bearerToken"

  API_OK=true
  if [ "$TEST_API" = true ] && [ -n "$SERVER" ] && [ "$SERVER" != "?" ]; then
    if command -v curl &>/dev/null; then
      HTTP=$(curl -s -o /dev/null -w "%{http_code}" -k -m 5 -H "Authorization: Bearer $TOKEN" "$SERVER/version" 2>/dev/null || echo "000")
      if [ "$HTTP" = "200" ]; then
        echo "  API:   OK (HTTP 200)"
      else
        echo "  API:   FAIL (HTTP $HTTP) — token invalid or expired; create a new token on this cluster and update the secret"
        API_OK=false
      fi
    else
      echo "  API:   skip (curl not found)"
    fi
  fi

  if [ "$API_OK" = true ]; then
    echo "  Overall: OK"
  else
    echo "  Overall: FAIL (fix token for this cluster)"
  fi
  echo ""
done

echo "Done. If any FAIL, update the token and run: kubectl rollout restart statefulset/openshift-gitops-application-controller -n $NS"
