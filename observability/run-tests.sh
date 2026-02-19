#!/usr/bin/env bash
# Observability tests: run curl against NFL Wallet APIs (dev, test, prod) to generate traffic
# visible in Kiali and Grafana. Set env vars below or pass as arguments.
#
# Usage:
#   ./run-tests.sh [dev|test|prod|all|loop]
#   DEV_HOST=... TEST_HOST=... PROD_HOST=... API_KEY_TEST=... API_KEY_PROD=... ./run-tests.sh all
#
# API keys: use the same values as in the Helm chart (nfl-wallet.apiKeys.customers, .bills, or .raiders
# in nfl-wallet-test/helm-values.yaml and nfl-wallet-prod/helm-values.yaml, or the Secret that backs them).

set -e

# --- Config (override with env vars) ---
# URL pattern: nfl-wallet-<env>.apps.<cluster-domain> (matches gateway route host in helm-values).
# Option 1: set CLUSTER_DOMAIN (e.g. cluster-lzdjz.lzdjz.sandbox1796.opentlc.com) to build https://nfl-wallet-ENV.apps.<cluster-domain>
# Option 2: set WILDCARD_URL with placeholder ENV (e.g. https://nfl-wallet-ENV.apps.cluster-lzdjz.lzdjz.sandbox1796.opentlc.com)
if [ -z "${WILDCARD_URL:-}" ] && [ -n "${CLUSTER_DOMAIN:-}" ]; then
  WILDCARD_URL="https://nfl-wallet-ENV.apps.${CLUSTER_DOMAIN}"
fi
if [ -n "${WILDCARD_URL:-}" ]; then
  if [[ "$WILDCARD_URL" =~ ^https?:// ]]; then
    SCHEME="${SCHEME:-${WILDCARD_URL%%://*}}"
    HOST_TEMPLATE="${WILDCARD_URL#*://}"
  else
    HOST_TEMPLATE="$WILDCARD_URL"
  fi
  DEV_HOST="${DEV_HOST:-${HOST_TEMPLATE//ENV/dev}}"
  TEST_HOST="${TEST_HOST:-${HOST_TEMPLATE//ENV/test}}"
  PROD_HOST="${PROD_HOST:-${HOST_TEMPLATE//ENV/prod}}"
else
  # Default: same wildcard pattern as gateway route in helm-values (override with your cluster domain)
  DEFAULT_CLUSTER_DOMAIN="cluster-lzdjz.lzdjz.sandbox1796.opentlc.com"
  DEV_HOST="${DEV_HOST:-nfl-wallet-dev.apps.${DEFAULT_CLUSTER_DOMAIN}}"
  TEST_HOST="${TEST_HOST:-nfl-wallet-test.apps.${DEFAULT_CLUSTER_DOMAIN}}"
  PROD_HOST="${PROD_HOST:-nfl-wallet-prod.apps.${DEFAULT_CLUSTER_DOMAIN}}"
fi
# Blue/Green canary hostname (when blueGreen.enabled and blueGreen.hostname are set in prod)
if [ -n "${CLUSTER_DOMAIN:-}" ]; then
  CANARY_HOST="${CANARY_HOST:-nfl-wallet-canary.apps.${CLUSTER_DOMAIN}}"
else
  CANARY_HOST="${CANARY_HOST:-nfl-wallet-canary.apps.${DEFAULT_CLUSTER_DOMAIN}}"
fi
SCHEME="${SCHEME:-https}"
# Default API key for testing (matches helm-values apiKeys.customers default)
API_KEY_TEST="${API_KEY_TEST:-nfl-wallet-customers-key}"
API_KEY_PROD="${API_KEY_PROD:-nfl-wallet-customers-key}"
LOOP_COUNT="${LOOP_COUNT:-20}"

# Base path for APIs (adjust if your routes use /customers instead of /api/customers)
API_PATH="${API_PATH:-/api}"

curl_silent() {
  curl -s -o /dev/null -w "%{http_code}" "$@"
}

curl_verbose() {
  curl -s -w "\nHTTP_CODE:%{http_code}\n" "$@"
}

# --- Dev (no auth) ---
run_dev() {
  echo "=== Dev @ ${SCHEME}://${DEV_HOST} (no auth) ==="
  curl_silent "${SCHEME}://${DEV_HOST}/" && echo " GET /"
  curl_verbose "${SCHEME}://${DEV_HOST}${API_PATH}/customers" && echo ""
  curl_verbose "${SCHEME}://${DEV_HOST}${API_PATH}/bills"    && echo ""
  curl_verbose "${SCHEME}://${DEV_HOST}${API_PATH}/raiders"  && echo ""
}

# --- Test (API key) ---
run_test() {
  if [ -z "$API_KEY_TEST" ]; then
    echo "=== Test @ ${SCHEME}://${TEST_HOST} (set API_KEY_TEST to run) ==="
    return 0
  fi
  echo "=== Test @ ${SCHEME}://${TEST_HOST} (with API key) ==="
  curl_verbose -H "X-Api-Key: ${API_KEY_TEST}" "${SCHEME}://${TEST_HOST}${API_PATH}/customers" && echo ""
  curl_verbose -H "X-Api-Key: ${API_KEY_TEST}" "${SCHEME}://${TEST_HOST}${API_PATH}/bills"    && echo ""
  curl_verbose -H "X-Api-Key: ${API_KEY_TEST}" "${SCHEME}://${TEST_HOST}${API_PATH}/raiders"  && echo ""
}

# --- Prod (API key) ---
run_prod() {
  if [ -z "$API_KEY_PROD" ]; then
    echo "=== Prod @ ${SCHEME}://${PROD_HOST} (set API_KEY_PROD to run) ==="
    return 0
  fi
  echo "=== Prod @ ${SCHEME}://${PROD_HOST} (with API key) ==="
  curl_verbose -H "X-Api-Key: ${API_KEY_PROD}" "${SCHEME}://${PROD_HOST}${API_PATH}/customers" && echo ""
  curl_verbose -H "X-Api-Key: ${API_KEY_PROD}" "${SCHEME}://${PROD_HOST}${API_PATH}/bills"    && echo ""
  curl_verbose -H "X-Api-Key: ${API_KEY_PROD}" "${SCHEME}://${PROD_HOST}${API_PATH}/raiders"  && echo ""
  echo "  (401? Apply kuadrant-system/api-key-secrets.yaml on the managed cluster — docs §6.5)"
}

# --- Blue/Green canary (prod HTTPRoute canary hostname; uses prod API key) ---
run_canary() {
  if [ -z "$API_KEY_PROD" ]; then
    echo "=== Canary @ ${SCHEME}://${CANARY_HOST} (set API_KEY_PROD to run) ==="
    return 0
  fi
  echo "=== Canary (blue/green) @ ${SCHEME}://${CANARY_HOST} (with API key) ==="
  curl_verbose -H "X-Api-Key: ${API_KEY_PROD}" "${SCHEME}://${CANARY_HOST}${API_PATH}/customers" && echo ""
  curl_verbose -H "X-Api-Key: ${API_KEY_PROD}" "${SCHEME}://${CANARY_HOST}${API_PATH}/bills"    && echo ""
  curl_verbose -H "X-Api-Key: ${API_KEY_PROD}" "${SCHEME}://${CANARY_HOST}${API_PATH}/raiders"  && echo ""
  echo "  (401? Same as prod: API key secrets in kuadrant-system on the managed cluster — docs §6.5)"
}

# --- Loop to generate sustained traffic (for Kiali / Grafana) ---
run_loop() {
  local url code ok=0 bad=0
  echo "=== Generating ${LOOP_COUNT} requests per API (dev @ ${DEV_HOST}) ==="
  for i in $(seq 1 "${LOOP_COUNT}"); do
    for path in customers bills raiders; do
      url="${SCHEME}://${DEV_HOST}${API_PATH}/${path}"
      code=$(curl_silent "$url")
      [ "$code" = "200" ] && ok=$((ok+1)) || bad=$((bad+1))
    done
  done
  echo "Dev: ${ok} x 200, ${bad} x non-200. If 503: check route and pods on that cluster (see docs §6.4)."
  [ "$bad" -gt 0 ] && [ "$ok" -eq 0 ] && echo "Tip: With ACM, use the managed cluster domain (e.g. east/west), not the hub. Set CLUSTER_DOMAIN to the clusterDomain from app-nfl-wallet-acm.yaml."
  echo "Done. Check Kiali and Grafana for traffic."
  if [ -n "$API_KEY_TEST" ]; then
    ok=0; bad=0
    for i in $(seq 1 "${LOOP_COUNT}"); do
      for path in customers bills; do
        code=$(curl_silent -H "X-Api-Key: ${API_KEY_TEST}" "${SCHEME}://${TEST_HOST}${API_PATH}/${path}")
        [ "$code" = "200" ] && ok=$((ok+1)) || bad=$((bad+1))
      done
    done
    echo "Test: ${ok} x 200, ${bad} x non-200"
  fi
  if [ -n "$API_KEY_PROD" ]; then
    ok=0; bad=0
    for i in $(seq 1 "${LOOP_COUNT}"); do
      for path in customers bills; do
        code=$(curl_silent -H "X-Api-Key: ${API_KEY_PROD}" "${SCHEME}://${PROD_HOST}${API_PATH}/${path}")
        [ "$code" = "200" ] && ok=$((ok+1)) || bad=$((bad+1))
      done
    done
    echo "Prod: ${ok} x 200, ${bad} x non-200"
  fi
}

# --- Main ---
case "${1:-all}" in
  dev)    run_dev ;;
  test)   run_test ;;
  prod)   run_prod ;;
  canary) run_canary ;;
  all)    run_dev; run_test; run_prod ;;
  loop)   run_loop ;;
  *)
    echo "Usage: $0 [dev|test|prod|canary|all|loop]"
    echo "  dev    - hit dev APIs (no auth)"
    echo "  test   - hit test APIs (requires API_KEY_TEST)"
    echo "  prod   - hit prod APIs (requires API_KEY_PROD)"
    echo "  canary - hit blue/green canary host (requires API_KEY_PROD, CANARY_HOST)"
    echo "  all    - run dev, test, prod (default)"
    echo "  loop   - send ${LOOP_COUNT} requests per API to generate traffic for Kiali/Grafana"
    echo ""
    echo "Env: CLUSTER_DOMAIN or WILDCARD_URL, DEV_HOST, TEST_HOST, PROD_HOST, CANARY_HOST, API_KEY_TEST, API_KEY_PROD, SCHEME (default https), API_PATH, LOOP_COUNT"
    exit 0
    ;;
esac
