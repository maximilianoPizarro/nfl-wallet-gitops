---
layout: default
title: Gateway Policies
---

# Gateway Policies

**AuthPolicy** (API key) and **RateLimitPolicy** are deployed with each app via **Kustomize overlays** in `nfl-wallet/overlays`. Argo CD syncs the Application and applies the overlay manifests to the corresponding namespace.

## Where the manifests live

| Environment | Overlay | Chart | Contents |
|-------------|---------|-------|----------|
| **dev** | `nfl-wallet/overlays/dev` | **0.1.3** | Gateway route, namespace-mesh (istio-injection), RHBK biometric login (via chart) |
| **test** | `nfl-wallet/overlays/test` | **0.1.3** | Gateway route, AuthPolicy, API keys, namespace-mesh, ESPN route, PlanPolicy, RHBK biometric login (via chart), OIDC policy (via chart) |
| **prod** | `nfl-wallet/overlays/prod` | **0.1.1** | Gateway route, canary route, AuthPolicy, API keys, namespace-mesh, PlanPolicy (no biometric login) |

For ACM (east/west), the `*-east` and `*-west` overlays have the same content but with cluster-specific domains.

## AuthPolicy: API key for test and prod

- **Goal:** Only consumers with a valid API key can call test and prod. Dev has no keys, so dev cannot access test/prod APIs.
- **Mechanism:** AuthPolicy in test and prod namespaces requires API key authentication. The selector uses the label `api: <namespace>` (e.g. `api: nfl-wallet-test`, `api: nfl-wallet-prod`). Clients must send the API key in the **`X-Api-Key`** header.

**Where API key Secrets are created:**  
Overlays include the Secrets directly in `api-keys-secret.yaml`. Kuadrant/Authorino looks them up by label `api: nfl-wallet-test` or `api: nfl-wallet-prod`. For production, use **Sealed Secrets** or **External Secrets**; do not commit real keys.

**Troubleshooting 401:** If test/prod return 401 with `X-Api-Key: nfl-wallet-customers-key`:

1. Verify Secrets exist: `kubectl get secrets -n nfl-wallet-test -l api=nfl-wallet-test`
2. Verify AuthPolicy: `kubectl get authpolicy -n nfl-wallet-test`
3. Verify Authorino: `kubectl get pods -n kuadrant-system -l app.kubernetes.io/name=authorino`

## OIDC Policy (test only — chart 0.1.3)

In **test**, the Helm chart's `gateway.oidcPolicy` is enabled. This creates Kuadrant **AuthPolicy** objects (one per API HTTPRoute: `api-customers`, `api-bills`, `api-raiders`) that validate **OIDC JWT tokens** issued by the RHBK realm.

- **Issuer URL**: `https://nfl-wallet-rhbk-neuroface-nfl-wallet-test.apps.<cluster-domain>/realms/neuroface`
- **Client ID**: `nfl-wallet-app`
- **Coexistence with API keys**: The OIDC AuthPolicy targets **individual HTTPRoutes** while the existing API key AuthPolicy in the overlay targets the **Gateway**. Both coexist — the OIDC policy takes precedence for the API routes it covers. The API key Secrets, overlay AuthPolicy, and PlanPolicy remain **unchanged**.

This allows testing the OIDC login flow (webapp → RHBK → biometric 2FA → JWT → API call) in test without modifying the existing API key authentication infrastructure.

## RHBK Biometric Login (dev / test — chart 0.1.3)

Chart 0.1.3 deploys [RHBK (Red Hat Build of Keycloak)](https://github.com/maximilianoPizarro/rhbk-biometric-flow) with [NeuroFace](https://github.com/maximilianoPizarro/neuroface) biometric facial authentication. The chart creates the RHBK Deployment, Service, and Route. The RHBK Route host follows the acronym pattern:

```
nfl-wallet-rhbk-neuroface-<namespace>.apps.<cluster-domain>
```

| Setting | Value |
|---------|-------|
| Camera resolution | 1920 × 1080 (FHD) |
| Realm | `neuroface` |
| Client | `nfl-wallet-app` |
| Confidence threshold | 65% |

The webapp connects to RHBK via `webapp.keycloakUrl` for OIDC login. After authentication (password + biometric 2FA), the webapp receives a JWT and includes it as a Bearer token in API calls.

## Canary Route (prod)

The prod overlay includes an additional **Route** for the canary host (`nfl-wallet-canary.apps.<cluster-domain>`). This Route points to the same gateway Service (`nfl-wallet-gateway-istio`) and enables blue/green traffic when the nfl-wallet chart creates the corresponding HTTPRoute.

The canary host is hardcoded in `nfl-wallet/overlays/prod/kustomization.yaml` (and in prod-east, prod-west). To change the domain, edit the patch in each overlay.

### Testing 0.1.3 via canary

To preview the biometric login (chart 0.1.3) in prod, update the ApplicationSet `chartVersion` for prod from `"0.1.1"` to `"0.1.3"` and add the RHBK Helm values. Access the canary URL (`nfl-wallet-canary.apps.<cluster-domain>`) to verify the deployment. Revert `chartVersion` to `"0.1.1"` to rollback.

## Namespace-mesh (Istio)

Each overlay includes a **namespace-mesh** manifest that applies labels to the namespace for the Istio mesh:

- **Dev / Test / Prod**: `istio-injection: enabled` (sidecar injection)

All three environments use the same mesh mode. Ambient mode (`istio.io/dataplane-mode: ambient`) was disabled in test/prod due to HBONE routing incompatibility between the Istio ingress gateway and ztunnel in Sail v1.27.x — the gateway could not establish HBONE connections to ambient-enrolled backends, resulting in HTTP 503 errors.

## Customization

- **Gateway name:** AuthPolicy and PlanPolicy reference the Gateway by name. Default is `nfl-wallet-gateway`. If the Stadium Wallet chart uses a different name, edit the overlays.
- **Cluster domain:** Edit the patches in each overlay to change the Route hosts. For RHBK, update `rhbk-neuroface.route.host` and `webapp.keycloakUrl` in the ApplicationSet Helm values.
- **API key labels:** If using a label other than `api`, update the selector in AuthPolicy and the Secret labels.
- **Camera resolution:** Change `rhbk-neuroface.biometric.cameraWidth` and `cameraHeight` in the ApplicationSet Helm values. Presets: QVGA 320×240, VGA 640×480, HD 1280×720, FHD 1920×1080.
- **OIDC policy:** To enable/disable OIDC in test, set `gateway.oidcPolicy.enabled` in the ApplicationSet Helm values.
