# Stadium Wallet – Routes (Gateway + Canary)

Kustomization to deploy Stadium Wallet routes:
- **dev/test**: **nfl-wallet-gateway** only (canary host is cluster-wide, prod only)
- **prod**: **nfl-wallet-gateway** + **nfl-wallet-canary** + API keys for AuthPolicy

Helm chart routes (`gateway.route`, `webapp.route`) are disabled in the ApplicationSet to avoid duplicates.

## Structure

```
nfl-wallet/
├── base/                    # gateway route (all envs)
│   ├── gateway-route.yaml
│   └── kustomization.yaml
├── base-canary/             # canary route (prod only)
│   ├── canary-route.yaml
│   └── kustomization.yaml
├── overlays/
│   ├── dev/                 # gateway only
│   ├── test/                # gateway + api-keys + auth-policy-patch
│   └── prod/                # gateway + canary + api-keys + auth-policy-patch
└── README.md
```

## Mesh (dev, test, prod)

Overlays include **namespace-mesh** labels to enable Istio mesh:
- **Dev**: `istio-injection=enabled` — sidecar mode (avoids "Out of mesh" when ambient labels are not picked up)
- **Test/Prod**: `istio.io/dataplane-mode=ambient`, `istio.io/use-waypoint=nfl-wallet-waypoint` — ambient mode, L7 via waypoint

## API keys (test and prod)

AuthPolicy in test and prod requires the `X-Api-Key` header **only for /api paths**. The frontend (/) allows anonymous browser access via `auth-policy-patch.yaml`. The chart creates Secrets in the app namespace (parameter `nfl-wallet.kuadrantNamespace`). Overlays also include backup secrets.

**Test with curl:**
```bash
# Prod - frontend (no key needed)
curl https://nfl-wallet-prod.apps.cluster-4cspb.4cspb.sandbox1414.opentlc.com/

# Prod - API (key required)
curl -H "X-Api-Key: nfl-wallet-customers-key" https://nfl-wallet-prod.apps.cluster-4cspb.4cspb.sandbox1414.opentlc.com/api-customers/Customers
```

The frontend must send `X-Api-Key` in API requests (fetch/axios). Configure the webapp to include the header when calling /api-bills, /api-customers, /api-raiders.

The AuthPolicy patch allows unauthenticated access to `/` (frontend); `/api` paths still require `X-Api-Key`.

For production: use Sealed Secrets or External Secrets; do not commit real keys.

## Cluster domain

Default: `cluster-4cspb.4cspb.sandbox1414.opentlc.com`. To change, edit the patches in each overlay.

## Deployment

Routes deploy together with the chart (2 sources per app in ApplicationSet nfl-wallet):
- `nfl-wallet-nfl-wallet-dev` → helm + nfl-wallet/overlays/dev
- `nfl-wallet-nfl-wallet-test` → helm + nfl-wallet/overlays/test
- `nfl-wallet-nfl-wallet-prod` → helm + nfl-wallet/overlays/prod

Manual:
```bash
kustomize build nfl-wallet/overlays/dev | kubectl apply -f -
```
