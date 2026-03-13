# Scripts for Stadium Wallet (east + west)

## Argo CD health: stop apps showing Progressing

If dev-west / test-west / prod-west stay **Progressing** even after sync, apply the health customizations on the **hub** and restart Argo CD:

`./scripts/argocd-reload-health-config.sh`

This patches `argocd-cm` (Deployment, HTTPRoute, AuthPolicy → Healthy) and restarts the server + application controller. Wait ~30 s and refresh the UI.

---

## Sync cluster secret from ACM (west 401 when token from SA fails)

If **west** (or east) still returns 401 after you created a token on the managed cluster and updated the secret, try using the credentials that ACM uses for that cluster. **On the hub:**

`./scripts/sync-cluster-secret-from-acm.sh west`

This looks for the secret `west-import` in `open-cluster-management-agent`, extracts server and token from the kubeconfig, and updates `cluster-west` in `openshift-gitops`. Then run `./scripts/verify-cluster-secrets.sh --test-api`. If the ACM import secret does not exist, create the token on the managed cluster again (see Refresh cluster secret below).

---

## Refresh cluster secret (fix 401 / credentials — east or west)

Use this to **regenerate the token on the managed cluster and update the secret on the hub** in two steps:

**Step 1 — On the managed cluster (east or west):**
```bash
oc login https://api.cluster-64k4b.64k4b.sandbox5146.opentlc.com:6443   # east
./scripts/refresh-cluster-secret.sh east
# Copy the token printed at the end.
```
Repeat for west: `oc login` to west, then `./scripts/refresh-cluster-secret.sh west`.

**Step 2 — On the hub:**
```bash
kubectl config use-context <hub>
./scripts/refresh-cluster-secret.sh east "<TOKEN_COPIED_FROM_STEP_1>"
# For west: ./scripts/refresh-cluster-secret.sh west "<WEST_TOKEN>"
```

The script creates namespace, ServiceAccount, RBAC, and token on the managed cluster; on the hub it patches the secret and restarts the application controller and repo server. Then run `./scripts/verify-cluster-secrets.sh --test-api` to confirm.

---

## Verify cluster secrets (east / west)

To check that the Argo CD cluster secrets have a valid structure and a real token (not the placeholder):

`./scripts/verify-cluster-secrets.sh`

With **context = hub**. To also test the token against each cluster API (requires `curl`):

`./scripts/verify-cluster-secrets.sh --test-api`

Prints OK or FAIL per secret; if API test fails, run `./scripts/refresh-cluster-secret.sh` for that cluster (see above).

---

## Update cluster secret token (fix Unauthorized / sync failed)

When apps fail with **"failed to discover server resources ... Unauthorized"**, the Argo CD cluster secret (east or west) on the hub has an expired token. Get a new token from the **managed** cluster (`oc whoami -t` with that cluster's context), then on the **hub** run:

`./scripts/update-cluster-secret-token.sh east 'sha256~...'` (or `west` and the west token)

The script patches the secret and restarts the application controller. Then sync the apps again.

---

## Fix managed cluster lease (AVAILABLE=Unknown)

If east2 or west2 show **AVAILABLE=Unknown** and condition **ManagedClusterLeaseUpdateStopped** on the hub, restart the klusterlet on each managed cluster so the registration agent updates the lease again.

`./scripts/fix-managed-cluster-lease.sh`

Requires kubeconfig contexts for east2 and west2. After running, wait 1–2 minutes and on the hub run: `kubectl get managedcluster east2 west2` — AVAILABLE should become **True**.

---

## Diagnose ApplicationSet (east vs west)

When **west is deployed but east is not** (or the opposite), run on the hub:

`./scripts/diagnose-applicationset.sh`

This lists the 6 Applications, cluster secrets, and ManagedClusters. It reminds you to ensure cluster names match and to hard-refresh the ApplicationSet if east apps are missing. See also [argocd-applicationset-fix.md](../docs/argocd-applicationset-fix.md) — "East not deploying / only west has apps".

---

## Force sync / refresh Applications (hub)

To force all 6 Applications to refresh and re-sync (OutOfSync -> Synced, Progressing -> Healthy when ready):

`./scripts/force-sync-apps.sh`

Or one-liner (run from repo root, context = hub):

```bash
for app in nfl-wallet-nfl-wallet-dev-east nfl-wallet-nfl-wallet-dev-west nfl-wallet-nfl-wallet-test-east nfl-wallet-nfl-wallet-test-west nfl-wallet-nfl-wallet-prod-east nfl-wallet-nfl-wallet-prod-west; do kubectl annotate application $app -n openshift-gitops argocd.argoproj.io/refresh=hard --overwrite; done
```

Then check: `kubectl get applications -n openshift-gitops`

---

## Fix ApplicationSet PlacementDecision RBAC (forbidden)

When the ApplicationSet controller shows **"PlacementDecision ... is forbidden ... cannot list"**, run on the **hub**:

`bash scripts/fix-applicationset-placement-rbac.sh`

The script discovers the exact PlacementDecision resource name on your cluster, applies ClusterRole + ClusterRoleBinding, restarts the controller, and verifies with `kubectl auth can-i`. If your controller uses a different ServiceAccount: `SA_NAME=that-sa-name bash scripts/fix-applicationset-placement-rbac.sh`

---

# Test scripts for Stadium Wallet APIs (east + west)

Scripts hit **east** and **west** for dev/test; **prod** is east only. 16 requests total.

## Prerequisites

- `curl`

## Cluster domains

The script uses by default:

- **East:** `cluster-64k4b.64k4b.sandbox5146.opentlc.com`
- **West:** `cluster-7rt9h.7rt9h.sandbox1900.opentlc.com`

Hosts: `nfl-wallet-<env>.apps.<domain>` (gateway), `webapp-nfl-wallet-<env>.apps.<domain>` (webapp).

To **use other domains** without editing the script, export the variables before running:

```bash
export EAST_DOMAIN="cluster-64k4b.64k4b.sandbox5146.opentlc.com"
export WEST_DOMAIN="cluster-7rt9h.7rt9h.sandbox1900.opentlc.com"
./scripts/test-apis.sh
```

```bash
# Default (valid TLS)
./scripts/test-apis.sh

# Skip TLS verify (e.g. self-signed)
./scripts/test-apis.sh --insecure

# Custom API keys (test/prod)
export API_KEY_CUSTOMERS=nfl-wallet-customers-key
export API_KEY_BILLS=nfl-wallet-bills-key
export API_KEY_RAIDERS=nfl-wallet-raiders-key
./scripts/test-apis.sh
```

## Request list (16)

| # | Cluster | Env  | Target        | Path / API key      |
|---|--------|------|---------------|---------------------|
| 1 | East   | dev  | Gateway       | GET /api/bills      |
| 2 | East   | dev  | Gateway       | GET /api/customers  |
| 3 | East   | dev  | Gateway       | GET /api/raiders    |
| 4 | West   | dev  | Gateway       | GET /api/bills      |
| 5 | West   | dev  | Gateway       | GET /api/customers  |
| 6 | East   | dev  | Webapp        | GET /               |
| 7 | West   | dev  | Webapp        | GET /               |
| 8 | East   | test | Gateway       | GET /api/bills (key)|
| 9 | West   | test | Gateway       | GET /api/customers (key) |
|10 | West   | test | Gateway       | GET /api/raiders (key)   |
|11 | East   | test | Webapp        | GET /               |
|12 | West   | test | Webapp        | GET /               |
|13 | East   | prod | Gateway       | GET /api/bills (key)|
|14 | East   | prod | Gateway       | GET /api/customers (key) |
|15 | East   | prod | Gateway       | GET /api/raiders (key)   |
|16 | East   | prod | Webapp        | GET /               |

**Prod** is east only: `https://nfl-wallet-prod.apps.cluster-64k4b.64k4b.sandbox5146.opentlc.com/`. Dev and test on east and west. Dev has no API key; test and prod use `X-Api-Key`. Format: `HTTP_CODE METHOD URL`.

---

# QA Test Plan (qa-test-plan.sh)

Automated test script based on the [Stadium Wallet QA Test Matrix](https://maximilianopizarro.github.io/stadium-wallet/) (§13). Covers all 10 test cases:

| ID    | Component     | What it tests                                                |
|-------|---------------|--------------------------------------------------------------|
| QA-01 | GitOps Sync   | ArgoCD applications are Healthy and Synced (requires `oc`)   |
| QA-02 | Ambient Mesh  | Pods have 1 container — no istio-proxy sidecar (requires `oc`) |
| QA-03 | Egress (ESPN) | api-bills and api-raiders reach ESPN API via dev endpoint    |
| QA-04 | RHDH Portal   | Manual — verify API catalog in Developer Hub UI              |
| QA-05 | Rate Limiting | Send 505 requests and verify 429 after quota                |
| QA-06 | AuthPolicy    | 403 without X-Api-Key on test/prod; 200 with key            |
| QA-07 | Cross-Cluster | Both east and west serve APIs and webapp                     |
| QA-08 | Observability | Grafana and Promxy routes reachable                          |
| QA-09 | Swagger UI    | /api/swagger accessible for each microservice                |
| QA-10 | Load Test     | Concurrent workers hit APIs; verify rate limiting            |

## Usage

```bash
# Run all tests
./scripts/qa-test-plan.sh

# Run specific tests
./scripts/qa-test-plan.sh QA-03 QA-06 QA-07

# Skip TLS verification
./scripts/qa-test-plan.sh --insecure

# Skip tests requiring oc CLI (QA-01, QA-02)
SKIP_OC=1 ./scripts/qa-test-plan.sh

# Custom cluster domains
export EAST_DOMAIN="cluster-64k4b.64k4b.sandbox5146.opentlc.com"
export WEST_DOMAIN="cluster-7rt9h.7rt9h.sandbox1900.opentlc.com"
./scripts/qa-test-plan.sh
```

## Env vars

| Variable             | Default                          | Description                              |
|----------------------|----------------------------------|------------------------------------------|
| `EAST_DOMAIN`        | cluster-64k4b...opentlc.com      | East cluster domain                      |
| `WEST_DOMAIN`        | cluster-7rt9h...opentlc.com      | West cluster domain                      |
| `API_KEY_CUSTOMERS`  | nfl-wallet-customers-key         | API key for customers                    |
| `API_KEY_BILLS`      | nfl-wallet-bills-key             | API key for bills                        |
| `API_KEY_RAIDERS`    | nfl-wallet-raiders-key           | API key for raiders                      |
| `RATE_LIMIT_REQUESTS`| 505                              | Requests to send in QA-05                |
| `LOAD_WORKERS`       | 10                               | Concurrent workers for QA-10             |
| `LOAD_REQUESTS`      | 20                               | Requests per worker for QA-10            |
| `SKIP_OC`            | 0                                | Set to 1 to skip oc-dependent tests      |
| `SCHEME`             | https                            | http or https                            |
