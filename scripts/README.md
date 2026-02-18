# Scripts for NFL Wallet (east + west)

## Argo CD health: stop apps showing Progressing

If dev-west / test-west / prod-west stay **Progressing** even after sync, apply the health customizations on the **hub** and restart Argo CD:

**Bash:** `./scripts/argocd-reload-health-config.sh`  
**PowerShell:** `.\scripts\argocd-reload-health-config.ps1`

This patches `argocd-cm` (Deployment, HTTPRoute, AuthPolicy → Healthy) and restarts the server + application controller. Wait ~30 s and refresh the UI.

---

## Fix managed cluster lease (AVAILABLE=Unknown)

If east2 or west2 show **AVAILABLE=Unknown** and condition **ManagedClusterLeaseUpdateStopped** on the hub, restart the klusterlet on each managed cluster so the registration agent updates the lease again.

**Bash:** `./scripts/fix-managed-cluster-lease.sh`  
**PowerShell:** `.\scripts\fix-managed-cluster-lease.ps1`

Requires kubeconfig contexts for east2 and west2. After running, wait 1–2 minutes and on the hub run: `kubectl get managedcluster east2 west2` — AVAILABLE should become **True**.

---

## Force sync / refresh Applications (hub)

To force all 6 Applications to refresh and re-sync (OutOfSync -> Synced, Progressing -> Healthy when ready):

**Bash:** `./scripts/force-sync-apps.sh`  
**PowerShell:** `.\scripts\force-sync-apps.ps1`

Or one-liner (run from repo root, context = hub):

```bash
for app in nfl-wallet-nfl-wallet-dev-east nfl-wallet-nfl-wallet-dev-west nfl-wallet-nfl-wallet-test-east nfl-wallet-nfl-wallet-test-west nfl-wallet-nfl-wallet-prod-east nfl-wallet-nfl-wallet-prod-west; do kubectl annotate application $app -n openshift-gitops argocd.argoproj.io/refresh=hard --overwrite; done
```

Then check: `kubectl get applications -n openshift-gitops`

---

# Test scripts for NFL Wallet APIs (east + west)

Scripts hit both **east** and **west** clusters for **dev**, **test**, and **prod** (gateway APIs and webapp). Minimum 18 requests.

## Prerequisites

- **Bash:** `curl`
- **PowerShell:** PowerShell 6+ recommended for `-Insecure` (SkipCertificateCheck). On Windows PowerShell 5.1, omit `-Insecure` or use valid TLS.

## Domains (from ApplicationSet)

- **East:** `cluster-s6krm.s6krm.sandbox3480.opentlc.com`
- **West:** `cluster-9nvg4.dynamic.redhatworkshops.io`

Host pattern: `nfl-wallet-<env>.apps.<domain>` (gateway), `webapp-nfl-wallet-<env>.apps.<domain>` (webapp).

## Bash (Linux / Git Bash / WSL)

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

## PowerShell

```powershell
# Default
.\scripts\test-apis.ps1

# Skip TLS verify (PowerShell 6+)
.\scripts\test-apis.ps1 -Insecure

# Custom API keys
$env:API_KEY_CUSTOMERS = "nfl-wallet-customers-key"
$env:API_KEY_BILLS = "nfl-wallet-bills-key"
$env:API_KEY_RAIDERS = "nfl-wallet-raiders-key"
.\scripts\test-apis.ps1
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
