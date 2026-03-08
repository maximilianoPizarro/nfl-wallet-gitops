---
layout: default
title: Gateway Policies
---

# Gateway Policies

**AuthPolicy** (API key) and **RateLimitPolicy** are deployed with each app via **Kustomize overlays** in `nfl-wallet/overlays`. Argo CD syncs the Application and applies the overlay manifests to the corresponding namespace.

## Where the manifests live

| Environment | Overlay | Contents |
|-------------|---------|----------|
| **dev** | `nfl-wallet/overlays/dev` | Gateway route, namespace-mesh (istio-injection) |
| **test** | `nfl-wallet/overlays/test` | Gateway route, AuthPolicy, API keys, namespace-mesh, ESPN route, PlanPolicy, Telemetry |
| **prod** | `nfl-wallet/overlays/prod` | Gateway route, canary route, AuthPolicy, API keys, namespace-mesh, PlanPolicy, Telemetry |

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

## Canary Route (prod)

The prod overlay includes an additional **Route** for the canary host (`nfl-wallet-canary.apps.<cluster-domain>`). This Route points to the same gateway Service (`nfl-wallet-gateway-istio`) and enables blue/green traffic when the nfl-wallet chart creates the corresponding HTTPRoute.

The canary host is hardcoded in `nfl-wallet/overlays/prod/kustomization.yaml` (and in prod-east, prod-west). To change the domain, edit the patch in each overlay.

## Namespace-mesh (Istio)

Each overlay includes a **namespace-mesh** manifest that applies labels to the namespace for the Istio mesh:

- **Dev**: `istio-injection: enabled` (sidecar mode)
- **Test/Prod**: `istio.io/dataplane-mode: ambient`, `istio.io/use-waypoint: nfl-wallet-waypoint` (ambient mode)

The waypoint `nfl-wallet-waypoint` is created by the Stadium Wallet chart when `waypoint.enabled: true`.

## Customization

- **Gateway name:** AuthPolicy and PlanPolicy reference the Gateway by name. Default is `nfl-wallet-gateway`. If the Stadium Wallet chart uses a different name, edit the overlays.
- **Cluster domain:** Edit the patches in each overlay to change the Route hosts.
- **API key labels:** If using a label other than `api`, update the selector in AuthPolicy and the Secret labels.
