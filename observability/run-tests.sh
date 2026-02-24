#!/usr/bin/env bash
# Observability tests: run curl against NFL Wallet APIs (dev, test, prod) to generate traffic
# visible in Kiali and Grafana. Set env vars below or pass as arguments.
#
# Usage:
#   ./run-tests.sh [dev|test|prod|canary|all|loop [dev|test|prod|canary]]
#   CLUSTER_DOMAIN=cluster-xxx.east.example.com ./run-tests.sh all   # evita 503 si el host por defecto apunta al hub
#   DEV_HOST=... TEST_HOST=... PROD_HOST=... API_KEY_TEST=... API_KEY_PROD=... ./run-tests.sh all
#
# Ejemplo listo para copiar/pegar (east + west, loop en ambos clusters):
#   export EAST_DOMAIN=cluster-s6krm.s6krm.sandbox3480.opentlc.com
#   export WEST_DOMAIN=cluster-2l9nd.dynamic.redhatworkshops.io
#   export API_KEY_TEST=nfl-wallet-customers-key
#   export API_KEY_PROD=nfl-wallet-customers-key
#   ./observability/run-tests.sh loop
#
# Opciones: dev | test | prod | canary | all | loop [dev|test|prod|canary]. Variables: CLUSTER_DOMAIN, EAST_DOMAIN, WEST_DOMAIN, DEV_HOST, TEST_HOST, PROD_HOST, CANARY_HOST, API_KEY_TEST, API_KEY_PROD, API_KEY_CUSTOMERS/BILLS/RAIDERS, SCHEME, API_PATH, LOOP_COUNT. Ver tabla en docs/observability.md.
#
# 503: suele ser host incorrecto (hub en vez del managed cluster) o Route/pods no listos. Usar CLUSTER_DOMAIN o EAST_DOMAIN/WEST_DOMAIN del managed cluster (east/west).
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
# Per-path keys (like scripts/test-apis.sh); fallback to API_KEY_TEST / API_KEY_PROD
API_KEY_CUSTOMERS="${API_KEY_CUSTOMERS:-$API_KEY_TEST}"
API_KEY_BILLS="${API_KEY_BILLS:-$API_KEY_TEST}"
API_KEY_RAIDERS="${API_KEY_RAIDERS:-$API_KEY_TEST}"
API_KEY_CUSTOMERS_PROD="${API_KEY_CUSTOMERS_PROD:-$API_KEY_PROD}"
API_KEY_BILLS_PROD="${API_KEY_BILLS_PROD:-$API_KEY_PROD}"
API_KEY_RAIDERS_PROD="${API_KEY_RAIDERS_PROD:-$API_KEY_PROD}"
LOOP_COUNT="${LOOP_COUNT:-20}"

# East/West cluster domains (like test-apis.sh). When both set, loops hit both clusters.
EAST_DOMAIN="${EAST_DOMAIN:-}"
WEST_DOMAIN="${WEST_DOMAIN:-}"

# Base path for APIs (adjust if your routes use /customers instead of /api/customers)
API_PATH="${API_PATH:-/api}"

curl_silent() {
  curl -s -o /dev/null -w "%{http_code}" "$@"
}

curl_verbose() {
  curl -s -w "\nHTTP_CODE:%{http_code}\n" "$@"
}

# Log each request like test-apis.sh: "code GET url"
log_request() {
  echo "$1 GET $2"
}

tip_503() {
  echo "  → 503: Revisar Route y pods del backend en ese cluster; con ACM usar el clusterDomain del managed cluster (east/west), no el hub. Definir CLUSTER_DOMAIN o DEV_HOST/TEST_HOST/PROD_HOST al cluster correcto."
}

# Resolve API key for path (customers|bills|raiders) and env (test|prod)
api_key_for() {
  local path="$1" env="$2"
  if [[ "$env" == "prod" ]]; then
    case "$path" in
      customers) echo "${API_KEY_CUSTOMERS_PROD}" ;;
      bills)     echo "${API_KEY_BILLS_PROD}" ;;
      raiders)   echo "${API_KEY_RAIDERS_PROD}" ;;
      *)         echo "${API_KEY_PROD}" ;;
    esac
  else
    case "$path" in
      customers) echo "${API_KEY_CUSTOMERS}" ;;
      bills)     echo "${API_KEY_BILLS}" ;;
      raiders)   echo "${API_KEY_RAIDERS}" ;;
      *)         echo "${API_KEY_TEST}" ;;
    esac
  fi
}

# --- Dev (no auth) ---
run_dev() {
  echo "=== Dev @ ${SCHEME}://${DEV_HOST} (no auth) ==="
  local code
  code=$(curl_silent "${SCHEME}://${DEV_HOST}/")
  echo "${code} GET /"
  curl_verbose "${SCHEME}://${DEV_HOST}${API_PATH}/customers" && echo ""
  curl_verbose "${SCHEME}://${DEV_HOST}${API_PATH}/bills"    && echo ""
  curl_verbose "${SCHEME}://${DEV_HOST}${API_PATH}/raiders"  && echo ""
  [ "$code" = "503" ] && tip_503
}

# --- Test (API key; per-path keys like test-apis.sh) ---
run_test() {
  if [ -z "$API_KEY_TEST" ]; then
    echo "=== Test @ ${SCHEME}://${TEST_HOST} (set API_KEY_TEST to run) ==="
    return 0
  fi
  echo "=== Test @ ${SCHEME}://${TEST_HOST} (with API key) ==="
  curl_verbose -H "X-Api-Key: $(api_key_for customers test)" "${SCHEME}://${TEST_HOST}${API_PATH}/customers" && echo ""
  curl_verbose -H "X-Api-Key: $(api_key_for bills test)" "${SCHEME}://${TEST_HOST}${API_PATH}/bills"    && echo ""
  curl_verbose -H "X-Api-Key: $(api_key_for raiders test)" "${SCHEME}://${TEST_HOST}${API_PATH}/raiders"  && echo ""
}

# --- Prod (API key; per-path keys like test-apis.sh) ---
run_prod() {
  if [ -z "$API_KEY_PROD" ]; then
    echo "=== Prod @ ${SCHEME}://${PROD_HOST} (set API_KEY_PROD to run) ==="
    return 0
  fi
  echo "=== Prod @ ${SCHEME}://${PROD_HOST} (with API key) ==="
  curl_verbose -H "X-Api-Key: $(api_key_for customers prod)" "${SCHEME}://${PROD_HOST}${API_PATH}/customers" && echo ""
  curl_verbose -H "X-Api-Key: $(api_key_for bills prod)" "${SCHEME}://${PROD_HOST}${API_PATH}/bills"    && echo ""
  curl_verbose -H "X-Api-Key: $(api_key_for raiders prod)" "${SCHEME}://${PROD_HOST}${API_PATH}/raiders"  && echo ""
  echo "  (401? Apply kuadrant-system/api-key-secrets.yaml on the managed cluster — docs §6.5)"
}

# --- Blue/Green canary (prod HTTPRoute canary hostname; per-path prod API keys) ---
run_canary() {
  if [ -z "$API_KEY_PROD" ]; then
    echo "=== Canary @ ${SCHEME}://${CANARY_HOST} (set API_KEY_PROD to run) ==="
    return 0
  fi
  echo "=== Canary (blue/green) @ ${SCHEME}://${CANARY_HOST} (with API key) ==="
  curl_verbose -H "X-Api-Key: $(api_key_for customers prod)" "${SCHEME}://${CANARY_HOST}${API_PATH}/customers" && echo ""
  curl_verbose -H "X-Api-Key: $(api_key_for bills prod)" "${SCHEME}://${CANARY_HOST}${API_PATH}/bills"    && echo ""
  curl_verbose -H "X-Api-Key: $(api_key_for raiders prod)" "${SCHEME}://${CANARY_HOST}${API_PATH}/raiders"  && echo ""
  echo "  (401? Same as prod: API key secrets in kuadrant-system on the managed cluster — docs §6.5)"
}

# --- Loop to generate sustained traffic (for Kiali / Grafana) ---
# Optional first arg: dev | test | prod | canary | all (default: all = dev + test + prod)
run_loop() {
  local target="${1:-all}"
  local url code ok=0 bad=0 count_503=0

  # Build host list for env (dev|test|prod|canary). When EAST_DOMAIN/WEST_DOMAIN set, hit both clusters like test-apis.sh.
  loop_hosts_for() {
    local env="$1"
    if [[ -n "$EAST_DOMAIN" ]] || [[ -n "$WEST_DOMAIN" ]]; then
      [[ -n "$EAST_DOMAIN" ]] && echo "east:${env}:${EAST_DOMAIN}"
      [[ -n "$WEST_DOMAIN" ]] && echo "west:${env}:${WEST_DOMAIN}"
    else
      case "$env" in
        dev)    echo "single:dev:${DEV_HOST}" ;;
        test)   echo "single:test:${TEST_HOST}" ;;
        prod)   echo "single:prod:${PROD_HOST}" ;;
        canary) echo "single:canary:${CANARY_HOST}" ;;
      esac
    fi
  }

  do_loop_dev() {
    local hosts cluster env_domain base_host
    hosts=$(loop_hosts_for dev)
    if [[ -z "$hosts" ]]; then
      hosts="single:dev:${DEV_HOST}"
    fi
    while IFS=: read -r cluster _ env_domain; do
      if [[ "$cluster" == "single" ]]; then
        base_host="${env_domain}"
      else
        base_host="nfl-wallet-dev.apps.${env_domain}"
      fi
      echo "=== Generating ${LOOP_COUNT} requests per API (dev @ ${base_host}${cluster:+ [${cluster}]}) ==="
      for i in $(seq 1 "${LOOP_COUNT}"); do
        for path in customers bills raiders; do
          url="${SCHEME}://${base_host}${API_PATH}/${path}"
          code=$(curl_silent "$url")
          log_request "$code" "$url"
          [ "$code" = "200" ] && ok=$((ok+1)) || { bad=$((bad+1)); [ "$code" = "503" ] && count_503=$((count_503+1)); }
        done
      done
    done <<< "$hosts"
    echo "Dev: ${ok} x 200, ${bad} x non-200${count_503:+ (${count_503} x 503)}."
    [ "$count_503" -gt 0 ] && tip_503
    [ "$bad" -gt 0 ] && [ "$ok" -eq 0 ] && [ "$count_503" -eq 0 ] && echo "Tip: With ACM, use the managed cluster domain (e.g. east/west), not the hub. Set CLUSTER_DOMAIN or EAST_DOMAIN/WEST_DOMAIN from app-nfl-wallet-acm.yaml."
  }

  do_loop_test() {
    [ -z "$API_KEY_TEST" ] && { echo "=== Test loop: set API_KEY_TEST to run ==="; return 0; }
    local hosts cluster env_domain base_host key
    hosts=$(loop_hosts_for test)
    [[ -z "$hosts" ]] && hosts="single:test:${TEST_HOST}"
    ok=0; bad=0
    while IFS=: read -r cluster _ env_domain; do
      if [[ "$cluster" == "single" ]]; then
        base_host="${env_domain}"
      else
        base_host="nfl-wallet-test.apps.${env_domain}"
      fi
      echo "=== Generating ${LOOP_COUNT} requests per API (test @ ${base_host}${cluster:+ [${cluster}]}) ==="
      for i in $(seq 1 "${LOOP_COUNT}"); do
        for path in customers bills raiders; do
          key=$(api_key_for "$path" test)
          url="${SCHEME}://${base_host}${API_PATH}/${path}"
          code=$(curl_silent -H "X-Api-Key: ${key}" "$url")
          log_request "$code" "$url"
          [ "$code" = "200" ] && ok=$((ok+1)) || bad=$((bad+1))
        done
      done
    done <<< "$hosts"
    echo "Test: ${ok} x 200, ${bad} x non-200"
  }

  do_loop_prod() {
    [ -z "$API_KEY_PROD" ] && { echo "=== Prod loop: set API_KEY_PROD to run ==="; return 0; }
    local hosts cluster env_domain base_host key
    hosts=$(loop_hosts_for prod)
    [[ -z "$hosts" ]] && hosts="single:prod:${PROD_HOST}"
    ok=0; bad=0
    while IFS=: read -r cluster _ env_domain; do
      if [[ "$cluster" == "single" ]]; then
        base_host="${env_domain}"
      else
        base_host="nfl-wallet-prod.apps.${env_domain}"
      fi
      echo "=== Generating ${LOOP_COUNT} requests per API (prod @ ${base_host}${cluster:+ [${cluster}]}) ==="
      for i in $(seq 1 "${LOOP_COUNT}"); do
        for path in customers bills raiders; do
          key=$(api_key_for "$path" prod)
          url="${SCHEME}://${base_host}${API_PATH}/${path}"
          code=$(curl_silent -H "X-Api-Key: ${key}" "$url")
          log_request "$code" "$url"
          [ "$code" = "200" ] && ok=$((ok+1)) || bad=$((bad+1))
        done
      done
    done <<< "$hosts"
    echo "Prod: ${ok} x 200, ${bad} x non-200"
  }

  do_loop_canary() {
    [ -z "$API_KEY_PROD" ] && { echo "=== Canary loop: set API_KEY_PROD to run ==="; return 0; }
    local hosts cluster env_domain base_host key
    hosts=$(loop_hosts_for canary)
    [[ -z "$hosts" ]] && hosts="single:canary:${CANARY_HOST}"
    ok=0; bad=0
    while IFS=: read -r cluster _ env_domain; do
      if [[ "$cluster" == "single" ]]; then
        base_host="${env_domain}"
      else
        base_host="nfl-wallet-canary.apps.${env_domain}"
      fi
      echo "=== Generating ${LOOP_COUNT} requests per API (canary @ ${base_host}${cluster:+ [${cluster}]}) ==="
      for i in $(seq 1 "${LOOP_COUNT}"); do
        for path in customers bills raiders; do
          key=$(api_key_for "$path" prod)
          url="${SCHEME}://${base_host}${API_PATH}/${path}"
          code=$(curl_silent -H "X-Api-Key: ${key}" "$url")
          log_request "$code" "$url"
          [ "$code" = "200" ] && ok=$((ok+1)) || bad=$((bad+1))
        done
      done
    done <<< "$hosts"
    echo "Canary: ${ok} x 200, ${bad} x non-200"
  }

  case "$target" in
    dev)    do_loop_dev ;;
    test)   do_loop_test ;;
    prod)   do_loop_prod ;;
    canary) do_loop_canary ;;
    all)
      do_loop_dev
      do_loop_test
      do_loop_prod
      ;;
    *)
      echo "Usage: $0 loop [dev|test|prod|canary|all]"
      echo "  loop       - dev + test + prod (default)"
      echo "  loop prod  - only prod (requires API_KEY_PROD)"
      echo "  loop canary - only canary host (requires API_KEY_PROD)"
      return 0
      ;;
  esac
  echo "Done. Check Kiali and Grafana for traffic."
}

# --- Main ---
case "${1:-all}" in
  dev)    run_dev ;;
  test)   run_test ;;
  prod)   run_prod ;;
  canary) run_canary ;;
  all)    run_dev; run_test; run_prod ;;
  loop)   run_loop "${2:-all}" ;;
  *)
    echo "Usage: $0 [dev|test|prod|canary|all|loop [target]]"
    echo "  dev    - hit dev APIs (no auth)"
    echo "  test   - hit test APIs (requires API_KEY_TEST)"
    echo "  prod   - hit prod APIs (requires API_KEY_PROD)"
    echo "  canary - hit blue/green canary host (requires API_KEY_PROD, CANARY_HOST)"
    echo "  all    - run dev, test, prod (default)"
    echo "  loop   - send ${LOOP_COUNT} requests per API (default: dev + test + prod)"
    echo "  loop dev|test|prod|canary - loop only that target (prod/canary require API_KEY_PROD)"
    echo ""
    echo "Env: CLUSTER_DOMAIN or WILDCARD_URL, DEV_HOST, TEST_HOST, PROD_HOST, CANARY_HOST, API_KEY_TEST, API_KEY_PROD, SCHEME (default https), API_PATH, LOOP_COUNT"
    echo "      EAST_DOMAIN, WEST_DOMAIN (when both set, loop hits east+west like scripts/test-apis.sh). Per-path keys: API_KEY_CUSTOMERS, API_KEY_BILLS, API_KEY_RAIDERS (test) and API_KEY_CUSTOMERS_PROD, API_KEY_BILLS_PROD, API_KEY_RAIDERS_PROD (prod)."
    exit 0
    ;;
esac
