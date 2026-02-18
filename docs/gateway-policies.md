# Gateway policies (subscription and Blue/Green)

Gateway policies for **subscription / credential-based access** (Spec §6) and **Blue/Green** (Spec §12) are deployed with each app via Helm **templates** in the corresponding app folder. Argo CD syncs the app (e.g. `nfl-wallet-test` or `nfl-wallet-prod`) and the templates are rendered with the app’s namespace and labels.

## Where the manifests live

| App / namespace   | Templates | Contents |
|-------------------|-----------|----------|
| **nfl-wallet-dev**  | `nfl-wallet-dev/templates/` | `podmonitor-istio-gateway.yaml` (PodMonitor for Istio gateway metrics) |
| **nfl-wallet-test** | `nfl-wallet-test/templates/` | `auth-policy.yaml` (AuthPolicy), `reference-grant.yaml` (ReferenceGrant), `podmonitor-istio-gateway.yaml` (PodMonitor for Istio gateway metrics) |
| **nfl-wallet-prod** | `nfl-wallet-prod/templates/` | `auth-policy.yaml` (AuthPolicy), `bluegreen-httproute.yaml` (Blue/Green HTTPRoute), `podmonitor-istio-gateway.yaml` (PodMonitor for Istio gateway metrics) |

No separate apply step is needed: when you deploy the test or prod Application (via ApplicationSet), Helm renders these templates into the app’s namespace with the correct labels.

## Labels on policy resources

Templates add standard labels so resources are tracked by GitOps and can be selected if needed:

- `app.kubernetes.io/name: nfl-wallet`
- `app.kubernetes.io/instance: {{ .Release.Name }}` (e.g. release name from Argo CD)
- `app.kubernetes.io/managed-by: {{ .Release.Service }}`
- `app.kubernetes.io/component`: `auth-policy`, `reference-grant`, or `bluegreen-route`
- `app.kubernetes.io/part-of: nfl-wallet`

## Subscription: limit dev access to test and prod

- **Goal:** Only consumers with valid API keys for test or prod can call those environments. Dev has no test/prod keys, so dev is denied access to test and prod APIs.
- **Mechanism:** AuthPolicy in test and prod namespaces requires API key authentication. The selector uses the **namespace** as the label value: `api: <Release.Namespace>` (e.g. `api: nfl-wallet-test`, `api: nfl-wallet-prod`). Clients must send the API key in the **`X-Api-Key`** header.

**Where to create API key Secrets:**  
With Kuadrant, when `allNamespaces` is `false` (default), API key Secrets **must be in the same namespace as the Kuadrant CR** (`kuadrant-system`). This repo provides **`kuadrant-system/api-key-secrets.yaml`** – 6 Secrets in `kuadrant-system` (3 test, 3 prod) with labels `api: nfl-wallet-test` / `api: nfl-wallet-prod` and `authorino.kuadrant.io/managed-by: authorino`. Apply once: `kubectl apply -f kuadrant-system/api-key-secrets.yaml`. If your Authorino CR name differs, edit that label in the file.

**Troubleshooting 401:** If test/prod return 401 with `X-Api-Key: nfl-wallet-customers-key`:

1. **Apply secrets in kuadrant-system:** `kubectl apply -f kuadrant-system/api-key-secrets.yaml`
2. **Check:** `kubectl get secrets -n kuadrant-system -l 'api in (nfl-wallet-test, nfl-wallet-prod)'`
3. If Authorino CR name is not `authorino`, edit `authorino.kuadrant.io/managed-by` in that manifest and re-apply.

## Blue/Green with test and prod namespaces

- **Goal:** One hostname that splits traffic by weight between the test (blue) and prod (green) namespaces.
- **Mechanism:** The HTTPRoute in `nfl-wallet-prod/templates/bluegreen-httproute.yaml` is **only created when `nfl-wallet.blueGreen.enabled` is `true`** in `nfl-wallet-prod/helm-values.yaml`. By default it is `false` so the route is not applied until the target Gateway exists and allows routes from the prod namespace. When enabled, the route has two backendRefs (prod and test) with weights (default 90/10). The ReferenceGrant in `nfl-wallet-test/templates/reference-grant.yaml` allows the prod HTTPRoute to reference the Service in the test namespace.

Enable Blue/Green only after confirming the Gateway exists (`kubectl get gateway -n nfl-wallet-prod`) and that it accepts routes from that namespace. Then set `blueGreen.enabled: true` in prod helm-values.

## Customization

- **Gateway name:** The AuthPolicy and Blue/Green HTTPRoute target the Gateway by name. This is configurable via **`nfl-wallet.gatewayPolicyGatewayName`** in `helm-values.yaml` (test and prod). Default in the template is `nfl-wallet-gateway-istio`; if your chart creates a Gateway with another name (e.g. `gateway`), set `gatewayPolicyGatewayName: "gateway"`. To see the actual name: `kubectl get gateway -n nfl-wallet-test` (or `nfl-wallet-prod`).
- **Blue/Green hostname/weights:** Edit `nfl-wallet-prod/templates/bluegreen-httproute.yaml` (hostnames, backendRefs[].weight).
- **API key label key:** If you use a label key other than `api`, update the AuthPolicy `selector.matchLabels` in the templates to match your Secrets.
