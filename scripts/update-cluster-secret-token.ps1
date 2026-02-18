# Update the Argo CD cluster secret (east or west) with a new bearer token.
# Run with kubectl context = HUB. Get token from the managed cluster: oc whoami -t
#
# Usage: .\scripts\update-cluster-secret-token.ps1 -Cluster east -Token "sha256~xxx..."
# Example: .\scripts\update-cluster-secret-token.ps1 -Cluster east -Token (oc whoami -t)

param(
    [Parameter(Mandatory=$true)]
    [ValidateSet("east","west")]
    [string]$Cluster,
    [Parameter(Mandatory=$true)]
    [string]$Token
)
$SecretName = "cluster-$Cluster"
$NS = "openshift-gitops"
$Json = @{tlsClientConfig=@{insecure=$true}; bearerToken=$Token} | ConvertTo-Json -Compress
$ConfigB64 = [Convert]::ToBase64String([Text.Encoding]::UTF8.GetBytes($Json))
kubectl patch secret $SecretName -n $NS --type=json -p="[{\`"op\`":\`"replace\`",\`"path\`":\`"/data/config\`",\`"value\`":\`"$ConfigB64\`"}]"
if ($LASTEXITCODE -ne 0) { exit $LASTEXITCODE }
Write-Host "Updated secret $SecretName. Restarting application controller..."
kubectl rollout restart statefulset/openshift-gitops-application-controller -n $NS
Write-Host "Done. Wait ~30s then sync the apps again."
