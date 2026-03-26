# Stadium Wallet – Routes (Gateway + Canary) + RHBK Biometric Login

Kustomization to deploy Stadium Wallet routes:
- **dev** (chart 0.1.3): **nfl-wallet-gateway** + **RHBK biometric login** (NeuroFace, FHD 1920×1080)
- **test** (chart 0.1.3): **nfl-wallet-gateway** + API keys + **RHBK biometric login** + **OIDC policy** (JWT validation on API HTTPRoutes)
- **prod** (chart 0.1.1): **nfl-wallet-gateway** + **nfl-wallet-canary** + API keys (no biometric login)

Helm chart routes (`gateway.route`, `webapp.route`) are disabled in the ApplicationSet to avoid duplicates. The RHBK Route is created by the chart (`rhbk-neuroface.route.enabled=true`) with the host set via Helm values.

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
│   ├── dev/                 # gateway only (RHBK via chart 0.1.3)
│   ├── test/                # gateway + api-keys + auth-policy-patch + OIDC (via chart 0.1.3)
│   └── prod/                # gateway + canary + api-keys + auth-policy-patch (chart 0.1.1)
└── README.md
```

## Helm chart versions

| Environment | Chart version | RHBK NeuroFace | OIDC policy | Camera resolution |
|-------------|---------------|----------------|-------------|-------------------|
| dev         | **0.1.3**     | Enabled        | Disabled    | 1920 × 1080 (FHD) |
| test        | **0.1.3**     | Enabled        | Enabled     | 1920 × 1080 (FHD) |
| prod        | **0.1.1**     | Disabled       | Disabled    | —                 |

## RHBK biometric login (dev / test)

Chart 0.1.3 deploys [RHBK](https://github.com/maximilianoPizarro/rhbk-biometric-flow) with NeuroFace biometric authentication. The RHBK Route host follows the acronym pattern:

```
nfl-wallet-rhbk-neuroface-<namespace>.apps.<cluster-domain>
```

The `webapp.keycloakUrl` points to the RHBK Route so the webapp can redirect to Keycloak for OIDC login. The realm is `neuroface` and the client is `nfl-wallet-app`.

## OIDC policy (test only)

In test, `gateway.oidcPolicy.enabled=true` creates Kuadrant AuthPolicy objects targeting each API HTTPRoute (`api-customers`, `api-bills`, `api-raiders`). These validate JWT tokens from the RHBK issuer (`/realms/neuroface`) without modifying the existing Gateway-level API key AuthPolicy in the overlay. The issuer URL is:

```
https://nfl-wallet-rhbk-neuroface-nfl-wallet-test.apps.<cluster-domain>/realms/neuroface
```

## Mesh (dev, test, prod)

Overlays include **namespace-mesh** labels to enable Istio mesh:
- **Dev**: `istio-injection=enabled` — sidecar mode (avoids "Out of mesh" when ambient labels are not picked up)
- **Test/Prod**: `istio-injection=enabled` — sidecar mode (ambient mode disabled due to HBONE incompatibility in Sail v1.27.x)

## API keys (test and prod)

AuthPolicy in test and prod requires the `X-Api-Key` header **only for /api paths**. The frontend (/) allows anonymous browser access via `auth-policy-patch.yaml`. The chart creates Secrets in the app namespace (parameter `nfl-wallet.kuadrantNamespace`). Overlays also include backup secrets.

**Test with curl:**
```bash
# Prod - frontend (no key needed)
curl https://nfl-wallet-prod.apps.cluster-64k4b.64k4b.sandbox5146.opentlc.com/

# Prod - API (key required)
curl -H "X-Api-Key: nfl-wallet-customers-key" https://nfl-wallet-prod.apps.cluster-64k4b.64k4b.sandbox5146.opentlc.com/api-customers/Customers
```

The frontend must send `X-Api-Key` in API requests (fetch/axios). Configure the webapp to include the header when calling /api-bills, /api-customers, /api-raiders.

The AuthPolicy patch allows unauthenticated access to `/` (frontend); `/api` paths still require `X-Api-Key`.

For production: use Sealed Secrets or External Secrets; do not commit real keys.

## Cluster domain

Default: `cluster-64k4b.64k4b.sandbox5146.opentlc.com`. To change, edit the patches in each overlay.

## Canary testing (0.1.3 on prod)

To preview chart 0.1.3 (biometric login) in the prod environment:

1. Edit the ApplicationSet: set `chartVersion: "0.1.3"` for the prod entry.
2. Add the `rhbk-neuroface` Helm values block (copy from the dev/test conditional).
3. Push to Git — Argo CD syncs the change. Access `nfl-wallet-canary.apps.<cluster-domain>` to test.
4. To rollback, revert to `chartVersion: "0.1.1"` and push.

## Deployment

Routes deploy together with the chart (2 sources per app in ApplicationSet nfl-wallet):
- `nfl-wallet-nfl-wallet-dev` → helm 0.1.3 + nfl-wallet/overlays/dev
- `nfl-wallet-nfl-wallet-test` → helm 0.1.3 + nfl-wallet/overlays/test
- `nfl-wallet-nfl-wallet-prod` → helm 0.1.1 + nfl-wallet/overlays/prod

Manual:
```bash
kustomize build nfl-wallet/overlays/dev | kubectl apply -f -
```
