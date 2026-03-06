# Patch required in nfl-wallet-gitops

The nfl-wallet-gitops chart creates an AuthPolicy **without conditions** that requires API key for all routes (including Swagger). That overrides or conflicts with the connectivity-link AuthPolicy that allows anonymous access to Swagger.

The ApplicationSet in connectivity-link already passes `authPolicy.enabled: "false"` to disable the chart's AuthPolicy. For it to work, you must apply this change in the **nfl-wallet-gitops** repo:

## Files to modify (in the nfl-wallet chart, not in this repo)

Wrap the AuthPolicy template content with a condition in:

- `nfl-wallet-prod/templates/auth-policy.yaml`
- `nfl-wallet-test/templates/auth-policy.yaml`

*Note: The nfl-wallet-* folders were removed; this repo uses Kustomize (nfl-wallet/overlays).*

## Change

**Before** (start of file):
```yaml
# AuthPolicy: restricts access to prod APIs...
apiVersion: kuadrant.io/v1
kind: AuthPolicy
metadata:
  ...
```

**After**:
```yaml
{{- if .Values.authPolicy.enabled | default true }}
# AuthPolicy: restricts access to prod APIs...
apiVersion: kuadrant.io/v1
kind: AuthPolicy
metadata:
  ...
```

And at the **end of the file**, add:
```yaml
{{- end }}
```

## Complete example (nfl-wallet-prod)

```yaml
{{- if .Values.authPolicy.enabled | default true }}
apiVersion: kuadrant.io/v1
kind: AuthPolicy
metadata:
  name: nfl-wallet-prod-auth
  namespace: {{ .Release.Namespace }}
  # ... rest same ...
spec:
  targetRef:
    # ...
  rules:
    authentication:
      "api-key":
        # ...
{{- end }}
```

With `authPolicy.enabled: "false"` in the ApplicationSet, the chart will not create its AuthPolicy and only the connectivity-link one will be used (with bypass for Swagger).

---

## PodMonitor: metrics port (15090)

The chart creates a PodMonitor for the gateway with port 15020, but Istio metrics are on **15090** (`/stats/prometheus`). The ApplicationSet already passes `nfl-wallet.observability.gatewayPodMonitor.port: "15090"`.

For it to work, the PodMonitor template in nfl-wallet-gitops must use the value:

```yaml
# In the PodMonitor template (e.g. podmonitor-gateway-rhobs.yaml)
podMetricsEndpoints:
  - port: {{ .Values.observability.gatewayPodMonitor.port | default "15020" }}
    path: /stats/prometheus
    interval: 30s
```

And in `values.yaml` or `helm-values.yaml`:
```yaml
observability:
  gatewayPodMonitor:
    port: "15020"  # default; ApplicationSet override: 15090
```
