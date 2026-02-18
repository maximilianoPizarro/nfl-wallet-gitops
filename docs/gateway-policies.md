# Gateway policies (subscription and Blue/Green)

Gateway policies for **subscription / credential-based access** (Spec §6) and **Blue/Green** (Spec §12) are deployed with each app via Helm **templates** in the corresponding app folder. Argo CD syncs the app (e.g. `nfl-wallet-test` or `nfl-wallet-prod`) and the templates are rendered with the app’s namespace and labels.

## Where the manifests live

| App / namespace   | Templates | Contents |
|-------------------|-----------|----------|
| **nfl-wallet-test** | `nfl-wallet-test/templates/` | `auth-policy.yaml` (AuthPolicy), `reference-grant.yaml` (ReferenceGrant for Blue/Green) |
| **nfl-wallet-prod** | `nfl-wallet-prod/templates/` | `auth-policy.yaml` (AuthPolicy), `bluegreen-httproute.yaml` (Blue/Green HTTPRoute) |
| **nfl-wallet-dev**  | — | No gateway policies (dev is open; no API key required) |

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
- **Mechanism:** AuthPolicy in test and prod namespaces requires API key authentication. The selector uses the **namespace** as the label value: `api: <Release.Namespace>` (e.g. `api: nfl-wallet-test`, `api: nfl-wallet-prod`).

**Required labels on API key Secrets:**  
Label your API key Secrets in `nfl-wallet-test` and `nfl-wallet-prod` so the AuthPolicy selector matches:

- In **nfl-wallet-test**: `api: nfl-wallet-test`
- In **nfl-wallet-prod**: `api: nfl-wallet-prod`

Without these labels, Kuadrant/Authorino will not find the secrets and all requests will get 401.

## Blue/Green with test and prod namespaces

- **Goal:** One hostname that splits traffic by weight between the test (blue) and prod (green) namespaces.
- **Mechanism:** The HTTPRoute in `nfl-wallet-prod/templates/bluegreen-httproute.yaml` has two backendRefs (prod and test) with weights (default 90/10). The ReferenceGrant in `nfl-wallet-test/templates/reference-grant.yaml` allows the prod HTTPRoute to reference the Service in the test namespace.

To change weights or hostname, edit `nfl-wallet-prod/templates/bluegreen-httproute.yaml` (or add Helm values and use `{{ .Values... }}` in the template).

## Customization

- **Gateway name:** If the nfl-wallet chart creates a Gateway with a different name, change `name: nfl-wallet-gateway-istio` in the AuthPolicy and HTTPRoute templates.
- **Blue/Green hostname/weights:** Edit `nfl-wallet-prod/templates/bluegreen-httproute.yaml` (hostnames, backendRefs[].weight).
- **API key label key:** If you use a label key other than `api`, update the AuthPolicy `selector.matchLabels` in the templates to match your Secrets.
