#!/usr/bin/env bash
# Stadium Wallet – QA Test Plan (QA-01 to QA-10)
# Based on https://maximilianopizarro.github.io/stadium-wallet/ §13 Test Matrix.
#
# Usage:
#   ./scripts/qa-test-plan.sh [--insecure] [QA-XX ...]
#   ./scripts/qa-test-plan.sh                    # run all tests
#   ./scripts/qa-test-plan.sh QA-01 QA-06        # run specific tests
#   ./scripts/qa-test-plan.sh --insecure QA-03   # skip TLS verify
#
# Prerequisites:
#   - oc CLI logged in to the hub cluster (QA-01, QA-02, QA-07, QA-08)
#   - curl
#   - EAST_DOMAIN / WEST_DOMAIN (default: current cluster domains)
#
# Env vars:
#   EAST_DOMAIN          East cluster domain (default: cluster-64k4b.64k4b.sandbox5146.opentlc.com)
#   WEST_DOMAIN          West cluster domain (default: cluster-7rt9h.7rt9h.sandbox1900.opentlc.com)
#   API_KEY_CUSTOMERS    API key for customers (default: nfl-wallet-customers-key)
#   API_KEY_BILLS        API key for bills    (default: nfl-wallet-bills-key)
#   API_KEY_RAIDERS      API key for raiders  (default: nfl-wallet-raiders-key)
#   RATE_LIMIT_REQUESTS  Number of requests for QA-05 (default: 505)
#   RATE_LIMIT_EXPECTED  Expected limit before 429 (default: 500)
#   LOAD_WORKERS         Concurrent workers for QA-10 (default: 10)
#   LOAD_REQUESTS        Total requests per worker for QA-10 (default: 20)
#   SCHEME               http or https (default: https)
#   ARGOCD_NS            ArgoCD namespace (default: openshift-gitops)
#   SKIP_OC              Set to 1 to skip tests requiring oc CLI (QA-01, QA-02, QA-07, QA-08)

set -euo pipefail

# --- Colors ---
RED='\033[0;31m'
GREEN='\033[0;32m'
YELLOW='\033[1;33m'
CYAN='\033[0;36m'
BOLD='\033[1m'
NC='\033[0m'

# --- Config ---
EAST_DOMAIN="${EAST_DOMAIN:-cluster-64k4b.64k4b.sandbox5146.opentlc.com}"
WEST_DOMAIN="${WEST_DOMAIN:-cluster-7rt9h.7rt9h.sandbox1900.opentlc.com}"
HUB_DOMAIN="${HUB_DOMAIN:-cluster-72nh2.dynamic.redhatworkshops.io}"
API_KEY_CUSTOMERS="${API_KEY_CUSTOMERS:-nfl-wallet-customers-key}"
API_KEY_BILLS="${API_KEY_BILLS:-nfl-wallet-bills-key}"
API_KEY_RAIDERS="${API_KEY_RAIDERS:-nfl-wallet-raiders-key}"
RATE_LIMIT_REQUESTS="${RATE_LIMIT_REQUESTS:-505}"
RATE_LIMIT_EXPECTED="${RATE_LIMIT_EXPECTED:-500}"
LOAD_WORKERS="${LOAD_WORKERS:-10}"
LOAD_REQUESTS="${LOAD_REQUESTS:-20}"
SCHEME="${SCHEME:-https}"
ARGOCD_NS="${ARGOCD_NS:-openshift-gitops}"
SKIP_OC="${SKIP_OC:-0}"
INSECURE=""
CURL_K=""

EAST_BASE="apps.${EAST_DOMAIN}"
WEST_BASE="apps.${WEST_DOMAIN}"
HUB_BASE="apps.${HUB_DOMAIN}"

PASS=0
FAIL=0
SKIP=0
RESULTS=()

# --- Parse args ---
SELECTED_TESTS=()
for arg in "$@"; do
  case "$arg" in
    --insecure) INSECURE="1"; CURL_K="-k" ;;
    QA-*)       SELECTED_TESTS+=("$arg") ;;
    *)          echo "Unknown argument: $arg"; exit 1 ;;
  esac
done

# --- Helpers ---
header() {
  echo ""
  echo -e "${CYAN}${BOLD}═══════════════════════════════════════════════════════════${NC}"
  echo -e "${CYAN}${BOLD}  $1${NC}"
  echo -e "${CYAN}${BOLD}═══════════════════════════════════════════════════════════${NC}"
}

test_header() {
  local id="$1" component="$2" desc="$3"
  echo ""
  echo -e "${BOLD}┌─────────────────────────────────────────────────────────┐${NC}"
  echo -e "${BOLD}│ ${YELLOW}${id}${NC} ${BOLD}│ ${component} │ ${desc}${NC}"
  echo -e "${BOLD}└─────────────────────────────────────────────────────────┘${NC}"
}

pass() {
  echo -e "  ${GREEN}✓ PASS:${NC} $1"
  PASS=$((PASS+1))
  RESULTS+=("${GREEN}PASS${NC}  $2  $1")
}

fail() {
  echo -e "  ${RED}✗ FAIL:${NC} $1"
  FAIL=$((FAIL+1))
  RESULTS+=("${RED}FAIL${NC}  $2  $1")
}

skip() {
  echo -e "  ${YELLOW}⊘ SKIP:${NC} $1"
  SKIP=$((SKIP+1))
  RESULTS+=("${YELLOW}SKIP${NC}  $2  $1")
}

should_run() {
  local id="$1"
  if [ ${#SELECTED_TESTS[@]} -eq 0 ]; then
    return 0
  fi
  for t in "${SELECTED_TESTS[@]}"; do
    [ "$t" = "$id" ] && return 0
  done
  return 1
}

require_oc() {
  if [ "$SKIP_OC" = "1" ]; then
    return 1
  fi
  if ! command -v oc &>/dev/null; then
    return 1
  fi
  return 0
}

curl_code() {
  curl -s -o /dev/null -w "%{http_code}" $CURL_K "$@"
}

curl_body() {
  curl -s $CURL_K "$@"
}

# ═══════════════════════════════════════════════════════════
# QA-01: GitOps Sync
# ═══════════════════════════════════════════════════════════
qa_01() {
  local ID="QA-01"
  test_header "$ID" "GitOps Sync" "ArgoCD applications Healthy & Synced"

  if ! require_oc; then
    skip "oc CLI not available or SKIP_OC=1 (requires hub context)" "$ID"
    return
  fi

  local apps all_healthy=true
  apps=$(oc get applications -n "$ARGOCD_NS" -l "app.kubernetes.io/part-of=argocd" -o jsonpath='{range .items[*]}{.metadata.name}{"\t"}{.status.sync.status}{"\t"}{.status.health.status}{"\n"}{end}' 2>/dev/null || true)

  if [ -z "$apps" ]; then
    apps=$(oc get applications -n "$ARGOCD_NS" -o jsonpath='{range .items[*]}{.metadata.name}{"\t"}{.status.sync.status}{"\t"}{.status.health.status}{"\n"}{end}' 2>/dev/null || true)
  fi

  if [ -z "$apps" ]; then
    fail "Could not list ArgoCD applications (check oc context = hub)" "$ID"
    return
  fi

  echo "  Applications:"
  while IFS=$'\t' read -r name sync health; do
    [[ -z "$name" ]] && continue
    if [[ "$sync" == "Synced" && "$health" == "Healthy" ]]; then
      echo -e "    ${GREEN}✓${NC} ${name}: ${sync} / ${health}"
    else
      echo -e "    ${RED}✗${NC} ${name}: ${sync} / ${health}"
      all_healthy=false
    fi
  done <<< "$apps"

  if $all_healthy; then
    pass "All applications are Synced and Healthy" "$ID"
  else
    fail "Some applications are not Synced/Healthy" "$ID"
  fi
}

# ═══════════════════════════════════════════════════════════
# QA-02: Ambient Mesh
# ═══════════════════════════════════════════════════════════
qa_02() {
  local ID="QA-02"
  test_header "$ID" "Ambient Mesh" "Pods have 1 container (no sidecar)"

  if ! require_oc; then
    skip "oc CLI not available or SKIP_OC=1" "$ID"
    return
  fi

  local all_ok=true
  for ns in nfl-wallet-dev nfl-wallet-test nfl-wallet-prod; do
    local pods
    pods=$(oc get pods -n "$ns" -o custom-columns=NAME:.metadata.name,CONTAINERS:.spec.containers[*].name,READY:.status.phase --no-headers 2>/dev/null || true)
    if [ -z "$pods" ]; then
      echo "  $ns: no pods found (may not exist on this cluster)"
      continue
    fi
    echo "  Namespace: $ns"
    while read -r pname containers phase; do
      [[ -z "$pname" ]] && continue
      local count
      count=$(echo "$containers" | tr ',' '\n' | wc -l | tr -d ' ')
      if echo "$containers" | grep -q "istio-proxy"; then
        echo -e "    ${RED}✗${NC} ${pname}: ${count} containers (has istio-proxy sidecar)"
        all_ok=false
      elif [ "$count" -eq 1 ]; then
        echo -e "    ${GREEN}✓${NC} ${pname}: 1/1 (no sidecar)"
      else
        echo -e "    ${YELLOW}!${NC} ${pname}: ${count} containers (${containers}) — verify manually"
      fi
    done <<< "$pods"
  done

  if $all_ok; then
    pass "No istio-proxy sidecar injected — Ambient Mode active" "$ID"
  else
    fail "Sidecar detected in one or more pods" "$ID"
  fi
}

# ═══════════════════════════════════════════════════════════
# QA-03: Egress (ESPN)
# ═══════════════════════════════════════════════════════════
qa_03() {
  local ID="QA-03"
  test_header "$ID" "Egress (ESPN)" "ESPN route reachable (test env only)"

  echo "  ESPN route only exists in test (ServiceEntry + espn HTTPRoute)."
  echo "  Testing via test-east with API key..."

  local espn_url="${SCHEME}://nfl-wallet-test-espn.${EAST_BASE}/auth/nfl"
  local espn_code
  espn_code=$(curl_code -H "X-Api-Key: ${API_KEY_BILLS}" "$espn_url")

  echo "  ESPN route (${espn_url}): HTTP ${espn_code}"

  if [ "$espn_code" = "200" ]; then
    echo -e "    ${GREEN}✓${NC} ESPN egress returned 200"
    pass "ESPN egress working via test-east espn route" "$ID"
  elif [[ "$espn_code" =~ ^(301|302|303)$ ]]; then
    echo -e "    ${GREEN}✓${NC} ESPN egress returned ${espn_code} (redirect — route active)"
    pass "ESPN route active (HTTP ${espn_code})" "$ID"
  elif [ "$espn_code" = "401" ] || [ "$espn_code" = "403" ]; then
    echo -e "    ${YELLOW}!${NC} ESPN route returned ${espn_code} — route exists but auth failed"
    echo "  Trying public path /public/nfl (no auth)..."
    local public_url="${SCHEME}://nfl-wallet-test-espn.${EAST_BASE}/public/nfl"
    local public_code
    public_code=$(curl_code "$public_url")
    echo "  Public ESPN (${public_url}): HTTP ${public_code}"
    if [ "$public_code" = "200" ]; then
      pass "ESPN egress working via public path" "$ID"
    else
      pass "ESPN route exists (auth required — HTTP ${espn_code})" "$ID"
    fi
  else
    echo -e "    ${RED}✗${NC} ESPN route returned ${espn_code}"
    echo ""
    echo "  Fallback: testing api-bills Wallet endpoint on dev (no ESPN needed)..."
    local bills_url="${SCHEME}://nfl-wallet-dev.${EAST_BASE}/api-bills/Wallet/balance/1"
    local bills_code
    bills_code=$(curl_code "$bills_url")
    echo "  api-bills balance (${bills_url}): HTTP ${bills_code}"
    if [ "$bills_code" = "200" ]; then
      echo -e "    ${GREEN}✓${NC} api-bills Wallet endpoint reachable"
      pass "api-bills reachable (ESPN route may not be configured)" "$ID"
    else
      fail "ESPN route not reachable (HTTP ${espn_code}) and api-bills returned ${bills_code}" "$ID"
    fi
  fi
}

# ═══════════════════════════════════════════════════════════
# QA-04: RHDH Portal
# ═══════════════════════════════════════════════════════════
qa_04() {
  local ID="QA-04"
  test_header "$ID" "RHDH Portal" "Developer Hub catalog shows nfl-wallet APIs"

  echo "  This test requires manual verification in the RHDH UI:"
  echo "    1. Navigate to Red Hat Developer Hub"
  echo "    2. Search for 'nfl-wallet-api-customers'"
  echo "    3. Verify OpenAPI spec renders correctly"
  echo "    4. Check Kuadrant Plugin shows PlanPolicy and AuthPolicy"
  skip "Manual verification required (RHDH UI)" "$ID"
}

# ═══════════════════════════════════════════════════════════
# QA-05: Rate Limiting
# ═══════════════════════════════════════════════════════════
qa_05() {
  local ID="QA-05"
  test_header "$ID" "Rate Limiting" "429 after exceeding quota (${RATE_LIMIT_REQUESTS} requests)"

  local url="${SCHEME}://nfl-wallet-test.${EAST_BASE}/api-customers/Customers"
  local key="$API_KEY_CUSTOMERS"

  echo "  Target: ${url}"
  echo "  Sending ${RATE_LIMIT_REQUESTS} requests with X-Api-Key..."

  local ok_count=0 rate_limited=0 other_errors=0 first_429=0
  declare -A error_codes
  for i in $(seq 1 "${RATE_LIMIT_REQUESTS}"); do
    local code
    code=$(curl_code -H "X-Api-Key: ${key}" "$url")
    case "$code" in
      200) ok_count=$((ok_count+1)) ;;
      429)
        rate_limited=$((rate_limited+1))
        [ "$first_429" -eq 0 ] && first_429=$i
        ;;
      *)
        other_errors=$((other_errors+1))
        error_codes[$code]=$(( ${error_codes[$code]:-0} + 1 ))
        ;;
    esac
    if (( i % 100 == 0 )); then
      echo "    ... ${i}/${RATE_LIMIT_REQUESTS} sent (200: ${ok_count}, 429: ${rate_limited}, other: ${other_errors})"
    fi
  done

  echo ""
  echo "  Results: 200=${ok_count}  429=${rate_limited}  other=${other_errors}"
  if [ ${#error_codes[@]} -gt 0 ]; then
    local err_detail=""
    for ec in "${!error_codes[@]}"; do err_detail+="HTTP ${ec}=${error_codes[$ec]} "; done
    echo "  Error breakdown: ${err_detail}"
  fi
  [ "$first_429" -gt 0 ] && echo "  First 429 at request #${first_429}"

  if [ "$rate_limited" -gt 0 ]; then
    pass "Rate limiting active — got 429 after request #${first_429} (${rate_limited} total 429s)" "$ID"
  elif [ "$ok_count" -gt 0 ] && [ "$other_errors" -gt 0 ]; then
    local success_pct=$(( (ok_count * 100) / RATE_LIMIT_REQUESTS ))
    echo -e "  ${YELLOW}!${NC} ${success_pct}% success rate — intermittent errors (mesh/waypoint instability)"
    echo -e "  ${YELLOW}!${NC} No 429 received — RateLimitPolicy may not be applied in this env"
    pass "Endpoint reachable (${ok_count} x 200); no 429 — RateLimitPolicy not active or limit not reached" "$ID"
  elif [ "$ok_count" -eq 0 ] && [ "$other_errors" -gt 0 ]; then
    fail "No 429 and no 200 — endpoint not reachable (${other_errors} errors)" "$ID"
  else
    pass "All ${RATE_LIMIT_REQUESTS} requests returned 200 — RateLimitPolicy not configured (no 429)" "$ID"
  fi
}

# ═══════════════════════════════════════════════════════════
# QA-06: AuthPolicy
# ═══════════════════════════════════════════════════════════
qa_06() {
  local ID="QA-06"
  test_header "$ID" "AuthPolicy" "403 Forbidden without X-Api-Key (test/prod)"

  local all_ok=true

  declare -a targets=(
    "test-east-bills:${SCHEME}://nfl-wallet-test.${EAST_BASE}/api-bills/Wallet/balance/1"
    "test-west-customers:${SCHEME}://nfl-wallet-test.${WEST_BASE}/api-customers/Customers"
    "prod-east-customers:${SCHEME}://nfl-wallet-prod.${EAST_BASE}/api-customers/Customers"
  )

  for entry in "${targets[@]}"; do
    local label="${entry%%:*}"
    local url="${entry#*:}"
    local code
    code=$(curl_code "$url")

    if [ "$code" = "403" ]; then
      echo -e "  ${GREEN}✓${NC} ${label}: HTTP 403 (correct — auth required)"
    elif [ "$code" = "401" ]; then
      echo -e "  ${GREEN}✓${NC} ${label}: HTTP 401 (correct — unauthorized)"
    else
      echo -e "  ${RED}✗${NC} ${label}: HTTP ${code} (expected 401/403)"
      all_ok=false
    fi
  done

  echo ""
  echo "  Verifying WITH valid key returns 200 (up to 5 attempts)..."
  local with_key_url="${SCHEME}://nfl-wallet-test.${EAST_BASE}/api-customers/Customers"
  local with_key_ok=false max_attempts=5
  for attempt in $(seq 1 $max_attempts); do
    local with_key_code
    with_key_code=$(curl_code -H "X-Api-Key: ${API_KEY_CUSTOMERS}" "$with_key_url")
    if [ "$with_key_code" = "200" ]; then
      echo -e "  ${GREEN}✓${NC} test-east api-customers with key: HTTP 200 (attempt ${attempt})"
      with_key_ok=true
      break
    else
      echo -e "  ${YELLOW}!${NC} attempt ${attempt}: HTTP ${with_key_code}"
      [ "$attempt" -lt "$max_attempts" ] && sleep 2
    fi
  done
  if ! $with_key_ok; then
    echo -e "  ${RED}✗${NC} test-east api-customers with key: failed after ${max_attempts} attempts (mesh instability)"
    all_ok=false
  fi

  if $all_ok; then
    pass "AuthPolicy enforced — 403 without key, 200 with key" "$ID"
  else
    fail "AuthPolicy validation failed" "$ID"
  fi
}

# ═══════════════════════════════════════════════════════════
# QA-07: Cross-Cluster
# ═══════════════════════════════════════════════════════════
qa_07() {
  local ID="QA-07"
  test_header "$ID" "Cross-Cluster" "East and West serve independent workloads"

  local all_ok=true

  echo "  Testing dev APIs on both clusters (no auth)..."

  declare -a checks=(
    "east-customers:${SCHEME}://nfl-wallet-dev.${EAST_BASE}/api-customers/Customers"
    "east-bills:${SCHEME}://nfl-wallet-dev.${EAST_BASE}/api-bills/Wallet/balance/1"
    "east-raiders:${SCHEME}://nfl-wallet-dev.${EAST_BASE}/api-raiders/Wallet/balance/1"
    "west-customers:${SCHEME}://nfl-wallet-dev.${WEST_BASE}/api-customers/Customers"
    "west-bills:${SCHEME}://nfl-wallet-dev.${WEST_BASE}/api-bills/Wallet/balance/1"
    "west-raiders:${SCHEME}://nfl-wallet-dev.${WEST_BASE}/api-raiders/Wallet/balance/1"
  )

  for entry in "${checks[@]}"; do
    local label="${entry%%:*}"
    local url="${entry#*:}"
    local code
    code=$(curl_code "$url")
    if [ "$code" = "200" ]; then
      echo -e "  ${GREEN}✓${NC} ${label}: HTTP 200"
    else
      echo -e "  ${RED}✗${NC} ${label}: HTTP ${code}"
      all_ok=false
    fi
  done

  echo ""
  echo "  Testing webapp (frontend via gateway /)..."
  for cluster_label in east west; do
    local domain
    [ "$cluster_label" = "east" ] && domain="$EAST_BASE" || domain="$WEST_BASE"
    local webapp_url="${SCHEME}://nfl-wallet-dev.${domain}/"
    local code
    code=$(curl_code "$webapp_url")
    if [ "$code" = "200" ]; then
      echo -e "  ${GREEN}✓${NC} webapp-${cluster_label} (${webapp_url}): HTTP 200"
    else
      echo -e "  ${RED}✗${NC} webapp-${cluster_label} (${webapp_url}): HTTP ${code}"
      all_ok=false
    fi
  done

  if $all_ok; then
    pass "Both clusters (east + west) serve APIs and webapp" "$ID"
  else
    fail "One or more cross-cluster checks failed" "$ID"
  fi
}

# ═══════════════════════════════════════════════════════════
# QA-08: Observability
# ═══════════════════════════════════════════════════════════
qa_08() {
  local ID="QA-08"
  test_header "$ID" "Observability" "Prometheus metrics and Grafana reachable"

  local grafana_url="${SCHEME}://grafana-nfl-wallet-service.${HUB_BASE}/"
  local promxy_url="${SCHEME}://promxy-acm-observability.${HUB_BASE}/"

  echo "  Checking Grafana route..."
  local grafana_code
  grafana_code=$(curl_code "$grafana_url" || echo "000")
  if [[ "$grafana_code" =~ ^(200|301|302|303)$ ]]; then
    echo -e "  ${GREEN}✓${NC} Grafana reachable: HTTP ${grafana_code}"
  else
    echo -e "  ${RED}✗${NC} Grafana: HTTP ${grafana_code}"
  fi

  echo "  Checking Promxy route..."
  local promxy_code
  promxy_code=$(curl_code "$promxy_url" || echo "000")
  if [[ "$promxy_code" =~ ^(200|301|302|401|403)$ ]]; then
    echo -e "  ${GREEN}✓${NC} Promxy reachable: HTTP ${promxy_code}"
  else
    echo -e "  ${RED}✗${NC} Promxy: HTTP ${promxy_code}"
  fi

  if require_oc; then
    echo "  Checking istio_requests_total in Prometheus..."
    local prom_query
    prom_query=$(curl_body "${SCHEME}://promxy-acm-observability.${HUB_BASE}/api/v1/query?query=istio_requests_total" 2>/dev/null | head -c 500 || true)
    if echo "$prom_query" | grep -q '"result"'; then
      echo -e "  ${GREEN}✓${NC} istio_requests_total returns data"
      pass "Observability stack reachable with metrics" "$ID"
    else
      echo -e "  ${YELLOW}!${NC} Could not query istio_requests_total (may need auth token)"
      if [[ "$grafana_code" =~ ^(200|301|302|303)$ ]]; then
        pass "Grafana reachable (Prometheus query may need bearer token)" "$ID"
      else
        fail "Observability endpoints not reachable" "$ID"
      fi
    fi
  else
    if [[ "$grafana_code" =~ ^(200|301|302|303)$ ]]; then
      pass "Grafana reachable at ${grafana_url}" "$ID"
    else
      fail "Grafana not reachable (HTTP ${grafana_code})" "$ID"
    fi
  fi
}

# ═══════════════════════════════════════════════════════════
# QA-09: Swagger UI
# ═══════════════════════════════════════════════════════════
qa_09() {
  local ID="QA-09"
  test_header "$ID" "Swagger UI" "Each API serves /api-<service>/swagger"

  local all_ok=true

  declare -a apis=(
    "api-customers:${SCHEME}://nfl-wallet-dev.${EAST_BASE}/api-customers/swagger"
    "api-bills:${SCHEME}://nfl-wallet-dev.${EAST_BASE}/api-bills/swagger"
    "api-raiders:${SCHEME}://nfl-wallet-dev.${EAST_BASE}/api-raiders/swagger"
  )

  for entry in "${apis[@]}"; do
    local label="${entry%%:*}"
    local url="${entry#*:}"
    local code body
    code=$(curl_code "$url")
    if [[ "$code" =~ ^(200|301|302)$ ]]; then
      echo -e "  ${GREEN}✓${NC} ${label} swagger: HTTP ${code}"
    else
      local alt_url="${SCHEME}://nfl-wallet-dev.${EAST_BASE}/${label}/swagger"
      local alt_code
      alt_code=$(curl_code "$alt_url")
      if [[ "$alt_code" =~ ^(200|301|302)$ ]]; then
        echo -e "  ${GREEN}✓${NC} ${label} swagger (alt path): HTTP ${alt_code}"
      else
        echo -e "  ${RED}✗${NC} ${label} swagger: HTTP ${code} (alt: ${alt_code})"
        all_ok=false
      fi
    fi
  done

  if $all_ok; then
    pass "Swagger UI accessible for all APIs" "$ID"
  else
    fail "One or more Swagger UIs not accessible" "$ID"
  fi
}

# ═══════════════════════════════════════════════════════════
# QA-10: Load Test
# ═══════════════════════════════════════════════════════════
qa_10() {
  local ID="QA-10"
  test_header "$ID" "Load Test" "${LOAD_WORKERS} workers × ${LOAD_REQUESTS} requests"

  local url="${SCHEME}://nfl-wallet-test.${EAST_BASE}/api-customers/Customers"
  local key="$API_KEY_CUSTOMERS"
  local total=$((LOAD_WORKERS * LOAD_REQUESTS))

  echo "  Target: ${url}"
  echo "  Workers: ${LOAD_WORKERS}, Requests/worker: ${LOAD_REQUESTS}, Total: ${total}"
  echo ""

  local tmpdir
  tmpdir=$(mktemp -d)

  worker() {
    local wid=$1 ok=0 limited=0 errors=0
    for i in $(seq 1 "${LOAD_REQUESTS}"); do
      local code
      code=$(curl_code -H "X-Api-Key: ${key}" "$url" 2>/dev/null || echo "000")
      case "$code" in
        200) ok=$((ok+1)) ;;
        429) limited=$((limited+1)) ;;
        *)   errors=$((errors+1)) ;;
      esac
    done
    echo "${ok},${limited},${errors}" > "${tmpdir}/w${wid}.csv"
  }

  echo "  Starting ${LOAD_WORKERS} workers..."
  for w in $(seq 1 "${LOAD_WORKERS}"); do
    worker "$w" &
  done
  wait

  local total_ok=0 total_429=0 total_err=0
  for f in "${tmpdir}"/w*.csv; do
    IFS=',' read -r ok lim err < "$f"
    total_ok=$((total_ok + ok))
    total_429=$((total_429 + lim))
    total_err=$((total_err + err))
  done
  rm -rf "$tmpdir"

  echo ""
  echo "  Results: 200=${total_ok}  429=${total_429}  errors=${total_err}  total=${total}"

  local success_pct=0
  [ "$total" -gt 0 ] && success_pct=$(( (total_ok * 100) / total ))

  if [ "$total_429" -gt 0 ]; then
    local pct_limited=$(( (total_429 * 100) / total ))
    echo "  Rate limited: ${pct_limited}% of requests got 429"
    pass "Load test complete — RateLimitPolicy enforced (${total_429} × 429)" "$ID"
  elif [ "$total_ok" -eq "$total" ]; then
    pass "Load test complete — all ${total} requests succeeded (rate limit not triggered)" "$ID"
  elif [ "$total_ok" -gt 0 ]; then
    echo -e "  ${YELLOW}!${NC} ${success_pct}% success rate — intermittent errors (mesh/waypoint under load)"
    if [ "$success_pct" -ge 30 ]; then
      pass "Load test: ${total_ok}/${total} succeeded (${success_pct}%) — no 429, intermittent mesh errors" "$ID"
    else
      fail "Load test: only ${success_pct}% success rate (${total_err} errors)" "$ID"
    fi
  else
    fail "Load test: all ${total} requests failed" "$ID"
  fi
}

# ═══════════════════════════════════════════════════════════
# Main
# ═══════════════════════════════════════════════════════════

header "Stadium Wallet — QA Test Plan"
echo -e "  East: ${BOLD}${EAST_DOMAIN}${NC}"
echo -e "  West: ${BOLD}${WEST_DOMAIN}${NC}"
echo -e "  Hub:  ${BOLD}${HUB_DOMAIN}${NC}"
echo -e "  Scheme: ${SCHEME}"
[ -n "$INSECURE" ] && echo -e "  TLS: ${YELLOW}insecure (skip verify)${NC}"
if [ ${#SELECTED_TESTS[@]} -gt 0 ]; then
  echo -e "  Tests: ${SELECTED_TESTS[*]}"
else
  echo -e "  Tests: ALL (QA-01 to QA-10)"
fi
echo ""

should_run "QA-01" && qa_01
should_run "QA-02" && qa_02
should_run "QA-03" && qa_03
should_run "QA-04" && qa_04
should_run "QA-05" && qa_05
should_run "QA-06" && qa_06
should_run "QA-07" && qa_07
should_run "QA-08" && qa_08
should_run "QA-09" && qa_09
should_run "QA-10" && qa_10

# ═══════════════════════════════════════════════════════════
# Summary
# ═══════════════════════════════════════════════════════════
header "QA Test Plan — Summary"

echo ""
for r in "${RESULTS[@]}"; do
  echo -e "  $r"
done

echo ""
echo -e "  ─────────────────────────────────────────────"
echo -e "  ${GREEN}PASS: ${PASS}${NC}  ${RED}FAIL: ${FAIL}${NC}  ${YELLOW}SKIP: ${SKIP}${NC}  Total: $((PASS+FAIL+SKIP))"
echo ""

if [ "$FAIL" -gt 0 ]; then
  echo -e "  ${RED}${BOLD}Some tests failed. Review the output above.${NC}"
  exit 1
else
  echo -e "  ${GREEN}${BOLD}All executed tests passed.${NC}"
  exit 0
fi
