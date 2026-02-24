#!/usr/bin/env bash
# NFL Wallet – API test script (east + west dev/test; prod east only).
# 16 requests. Requires curl. For test/prod, X-Api-Key is required.
#
# Usage: ./scripts/test-apis.sh [--insecure]
# Optional: export API_KEY_CUSTOMERS=nfl-wallet-customers-key API_KEY_BILLS=nfl-wallet-bills-key API_KEY_RAIDERS=nfl-wallet-raiders-key

set -e
INSECURE="${1:-}"
CURL_OPTS="-s -o /dev/null -w '%{http_code}'"
[[ "$INSECURE" == "--insecure" ]] && CURL_OPTS="-k $CURL_OPTS"

# Cluster domains: *.apps.<domain>. Override with EAST_DOMAIN / WEST_DOMAIN if needed.
# East: cluster-s6krm.s6krm.sandbox3480.opentlc.com
# West: cluster-2l9nd.dynamic.redhatworkshops.io
EAST_DOMAIN="${EAST_DOMAIN:-cluster-s6krm.s6krm.sandbox3480.opentlc.com}"
WEST_DOMAIN="${WEST_DOMAIN:-cluster-2l9nd.dynamic.redhatworkshops.io}"

# API keys for test/prod (dev has no auth)
API_CUSTOMERS="${API_KEY_CUSTOMERS:-nfl-wallet-customers-key}"
API_BILLS="${API_KEY_BILLS:-nfl-wallet-bills-key}"
API_RAIDERS="${API_KEY_RAIDERS:-nfl-wallet-raiders-key}"

run() {
  local method="$1" url="$2" hdr="$3"
  local code
  if [[ -n "$hdr" ]]; then
    code=$(curl -X "$method" -H "$hdr" $CURL_OPTS "$url")
  else
    code=$(curl -X "$method" $CURL_OPTS "$url")
  fi
  echo "$code $method $url"
}

# --- DEV (no API key) ---
run GET "https://nfl-wallet-dev.apps.${EAST_DOMAIN}/api/bills"
run GET "https://nfl-wallet-dev.apps.${EAST_DOMAIN}/api/customers"
run GET "https://nfl-wallet-dev.apps.${EAST_DOMAIN}/api/raiders"
run GET "https://nfl-wallet-dev.apps.${WEST_DOMAIN}/api/bills"
run GET "https://nfl-wallet-dev.apps.${WEST_DOMAIN}/api/customers"
run GET "https://webapp-nfl-wallet-dev.apps.${EAST_DOMAIN}/"
run GET "https://webapp-nfl-wallet-dev.apps.${WEST_DOMAIN}/"

# --- TEST (with API key) ---
run GET "https://nfl-wallet-test.apps.${EAST_DOMAIN}/api/bills" "X-Api-Key: $API_BILLS"
run GET "https://nfl-wallet-test.apps.${WEST_DOMAIN}/api/customers" "X-Api-Key: $API_CUSTOMERS"
run GET "https://nfl-wallet-test.apps.${WEST_DOMAIN}/api/raiders" "X-Api-Key: $API_RAIDERS"
run GET "https://webapp-nfl-wallet-test.apps.${EAST_DOMAIN}/"
run GET "https://webapp-nfl-wallet-test.apps.${WEST_DOMAIN}/"

# --- PROD (with API key, east only: https://nfl-wallet-prod.apps.<east-domain>/) ---
run GET "https://nfl-wallet-prod.apps.${EAST_DOMAIN}/api/bills" "X-Api-Key: $API_BILLS"
run GET "https://nfl-wallet-prod.apps.${EAST_DOMAIN}/api/customers" "X-Api-Key: $API_CUSTOMERS"
run GET "https://nfl-wallet-prod.apps.${EAST_DOMAIN}/api/raiders" "X-Api-Key: $API_RAIDERS"
run GET "https://webapp-nfl-wallet-prod.apps.${EAST_DOMAIN}/"

echo "Done (16 requests: dev/test east+west, prod east only)."
