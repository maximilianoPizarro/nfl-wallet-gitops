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
SCHEME="${SCHEME:-https}"
API_KEY_TEST="${API_KEY_TEST:-}"
API_KEY_PROD="${API_KEY_PROD:-}"
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
  curl_verbose -H "Authorization: Bearer ${API_KEY_TEST}" "${SCHEME}://${TEST_HOST}${API_PATH}/customers" && echo ""
  curl_verbose -H "Authorization: Bearer ${API_KEY_TEST}" "${SCHEME}://${TEST_HOST}${API_PATH}/bills"    && echo ""
  curl_verbose -H "Authorization: Bearer ${API_KEY_TEST}" "${SCHEME}://${TEST_HOST}${API_PATH}/raiders"  && echo ""
}

# --- Prod (API key) ---
run_prod() {
  if [ -z "$API_KEY_PROD" ]; then
    echo "=== Prod @ ${SCHEME}://${PROD_HOST} (set API_KEY_PROD to run) ==="
    return 0
  fi
  echo "=== Prod @ ${SCHEME}://${PROD_HOST} (with API key) ==="
  curl_verbose -H "Authorization: Bearer ${API_KEY_PROD}" "${SCHEME}://${PROD_HOST}${API_PATH}/customers" && echo ""
  curl_verbose -H "Authorization: Bearer ${API_KEY_PROD}" "${SCHEME}://${PROD_HOST}${API_PATH}/bills"    && echo ""
  curl_verbose -H "Authorization: Bearer ${API_KEY_PROD}" "${SCHEME}://${PROD_HOST}${API_PATH}/raiders"  && echo ""
}

# --- Loop to generate sustained traffic (for Kiali / Grafana) ---
run_loop() {
  echo "=== Generating ${LOOP_COUNT} requests per API (dev) ==="
  for i in $(seq 1 "${LOOP_COUNT}"); do
    curl_silent "${SCHEME}://${DEV_HOST}${API_PATH}/customers"
    curl_silent "${SCHEME}://${DEV_HOST}${API_PATH}/bills"
    curl_silent "${SCHEME}://${DEV_HOST}${API_PATH}/raiders"
  done
  echo "Done. Check Kiali and Grafana for traffic."
  if [ -n "$API_KEY_TEST" ]; then
    for i in $(seq 1 "${LOOP_COUNT}"); do
      curl_silent -H "Authorization: Bearer ${API_KEY_TEST}" "${SCHEME}://${TEST_HOST}${API_PATH}/customers"
      curl_silent -H "Authorization: Bearer ${API_KEY_TEST}" "${SCHEME}://${TEST_HOST}${API_PATH}/bills"
    done
  fi
  if [ -n "$API_KEY_PROD" ]; then
    for i in $(seq 1 "${LOOP_COUNT}"); do
      curl_silent -H "Authorization: Bearer ${API_KEY_PROD}" "${SCHEME}://${PROD_HOST}${API_PATH}/customers"
      curl_silent -H "Authorization: Bearer ${API_KEY_PROD}" "${SCHEME}://${PROD_HOST}${API_PATH}/bills"
    done
  fi
}

# --- Main ---
case "${1:-all}" in
  dev)   run_dev ;;
  test)  run_test ;;
  prod)  run_prod ;;
  all)   run_dev; run_test; run_prod ;;
  loop)  run_loop ;;
  *)
    echo "Usage: $0 [dev|test|prod|all|loop]"
    echo "  dev   - hit dev APIs (no auth)"
    echo "  test  - hit test APIs (requires API_KEY_TEST)"
    echo "  prod  - hit prod APIs (requires API_KEY_PROD)"
    echo "  all   - run dev, test, prod (default)"
    echo "  loop  - send ${LOOP_COUNT} requests per API to generate traffic for Kiali/Grafana"
    echo ""
    echo "Env: CLUSTER_DOMAIN or WILDCARD_URL (e.g. https://nfl-wallet-ENV.apps.<cluster-domain>), DEV_HOST, TEST_HOST, PROD_HOST, API_KEY_TEST, API_KEY_PROD, SCHEME (default https), API_PATH, LOOP_COUNT"
    exit 0
    ;;
esac
