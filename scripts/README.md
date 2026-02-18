# Scripts for NFL Wallet (east + west)

## Argo CD health: stop apps showing Progressing

If dev-west / test-west / prod-west stay **Progressing** even after sync, apply the health customizations on the **hub** and restart Argo CD:

`./scripts/argocd-reload-health-config.sh`

This patches `argocd-cm` (Deployment, HTTPRoute, AuthPolicy → Healthy) and restarts the server + application controller. Wait ~30 s and refresh the UI.

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

## Force sync / refresh Applications (hub)

To force all 6 Applications to refresh and re-sync (OutOfSync -> Synced, Progressing -> Healthy when ready):

`./scripts/force-sync-apps.sh`

Or one-liner (run from repo root, context = hub):

```bash
for app in nfl-wallet-nfl-wallet-dev-east nfl-wallet-nfl-wallet-dev-west nfl-wallet-nfl-wallet-test-east nfl-wallet-nfl-wallet-test-west nfl-wallet-nfl-wallet-prod-east nfl-wallet-nfl-wallet-prod-west; do kubectl annotate application $app -n openshift-gitops argocd.argoproj.io/refresh=hard --overwrite; done
```

Then check: `kubectl get applications -n openshift-gitops`

---

# Test scripts for NFL Wallet APIs (east + west)

Scripts hit both **east** and **west** clusters for **dev**, **test**, and **prod** (gateway APIs and webapp). Minimum 18 requests.

## Prerequisites

- `curl`

## Domains (from ApplicationSet)

- **East:** `cluster-s6krm.s6krm.sandbox3480.opentlc.com`
- **West:** `cluster-9nvg4.dynamic.redhatworkshops.io`

Host pattern: `nfl-wallet-<env>.apps.<domain>` (gateway), `webapp-nfl-wallet-<env>.apps.<domain>` (webapp).

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

## Request list (18)

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
|15 | West   | prod | Gateway       | GET /api/raiders (key)   |
|16 | East   | prod | Webapp        | GET /               |
|17 | West   | prod | Webapp        | GET /               |

Dev has no API key; test and prod use `X-Api-Key` (values from `kuadrant-system/api-key-secrets.yaml`). Output format: `HTTP_CODE METHOD URL`.
