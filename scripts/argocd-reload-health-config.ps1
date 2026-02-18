# Apply argocd-cm health customizations and restart Argo CD so apps stop showing Progressing.
# Run from repo root with kubectl context = hub (openshift-gitops namespace).

$ErrorActionPreference = "Stop"
$ScriptDir = Split-Path -Parent $MyInvocation.MyCommand.Path
$RepoRoot = Resolve-Path (Join-Path $ScriptDir "..")
$PatchFile = Join-Path $RepoRoot "docs\argocd-cm-health-customizations.yaml"

if (-not (Test-Path $PatchFile)) {
  Write-Error "Patch file not found: $PatchFile"
  exit 1
}

Write-Host "Patching argocd-cm in openshift-gitops..."
kubectl patch configmap argocd-cm -n openshift-gitops --type merge --patch-file $PatchFile

Write-Host "Restarting Argo CD server..."
kubectl rollout restart deployment/openshift-gitops-server -n openshift-gitops

Write-Host "Restarting application controller (StatefulSet or Deployment)..."
kubectl get statefulset openshift-gitops-application-controller -n openshift-gitops 2>$null
if ($LASTEXITCODE -eq 0) {
  kubectl rollout restart statefulset/openshift-gitops-application-controller -n openshift-gitops
} else {
  kubectl get statefulset argocd-application-controller -n openshift-gitops 2>$null
  if ($LASTEXITCODE -eq 0) {
    kubectl rollout restart statefulset/argocd-application-controller -n openshift-gitops
  } else {
    kubectl get deployment openshift-gitops-application-controller -n openshift-gitops 2>$null
    if ($LASTEXITCODE -eq 0) {
      kubectl rollout restart deployment/openshift-gitops-application-controller -n openshift-gitops
    } else {
      kubectl get deployment argocd-application-controller -n openshift-gitops 2>$null
      if ($LASTEXITCODE -eq 0) {
        kubectl rollout restart deployment/argocd-application-controller -n openshift-gitops
      } else {
        Write-Host "No application controller found; list workloads:"
        kubectl get deploy,statefulset -n openshift-gitops
      }
    }
  }
}

Write-Host "Done. Wait ~30s then check app health in the Argo CD UI."
