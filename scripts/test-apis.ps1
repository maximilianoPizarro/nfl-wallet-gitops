# NFL Wallet – API test script (east + west, dev/test/prod). Minimum 10 requests.
# Usage: .\scripts\test-apis.ps1 [-Insecure]
# -Insecure requires PowerShell 6+ (SkipCertificateCheck). Optional env: API_KEY_CUSTOMERS, API_KEY_BILLS, API_KEY_RAIDERS.

param([switch]$Insecure)
if ($Insecure -and $PSVersionTable.PSVersion.Major -lt 6) {
    Write-Warning "-Insecure is ignored (SkipCertificateCheck requires PowerShell 6+)."
    $Insecure = $false
}

$ErrorActionPreference = "Stop"
$EastDomain = "cluster-s6krm.s6krm.sandbox3480.opentlc.com"
$WestDomain = "cluster-9nvg4.dynamic.redhatworkshops.io"
$ApiCustomers = if ($env:API_KEY_CUSTOMERS) { $env:API_KEY_CUSTOMERS } else { "nfl-wallet-customers-key" }
$ApiBills    = if ($env:API_KEY_BILLS)    { $env:API_KEY_BILLS } else { "nfl-wallet-bills-key" }
$ApiRaiders  = if ($env:API_KEY_RAIDERS)  { $env:API_KEY_RAIDERS } else { "nfl-wallet-raiders-key" }

function Invoke-Test {
    param([string]$Method, [string]$Url, [string]$ApiKeyHeader)
    $params = @{ Uri = $Url; Method = $Method; UseBasicParsing = $true }
    if ($Insecure) { $params["SkipCertificateCheck"] = $true }
    if ($ApiKeyHeader) { $params["Headers"] = @{ "X-Api-Key" = $ApiKeyHeader } }
    try {
        $r = Invoke-WebRequest @params
        $code = $r.StatusCode
    } catch {
        $code = $_.Exception.Response.StatusCode.value__
        if (-not $code) { $code = "Err" }
    }
    Write-Host "$code $Method $Url"
}

# DEV (no API key)
Invoke-Test GET "https://nfl-wallet-dev.apps.$EastDomain/api/bills"
Invoke-Test GET "https://nfl-wallet-dev.apps.$EastDomain/api/customers"
Invoke-Test GET "https://nfl-wallet-dev.apps.$EastDomain/api/raiders"
Invoke-Test GET "https://nfl-wallet-dev.apps.$WestDomain/api/bills"
Invoke-Test GET "https://nfl-wallet-dev.apps.$WestDomain/api/customers"
Invoke-Test GET "https://webapp-nfl-wallet-dev.apps.$EastDomain/"
Invoke-Test GET "https://webapp-nfl-wallet-dev.apps.$WestDomain/"

# TEST (with API key)
Invoke-Test GET "https://nfl-wallet-test.apps.$EastDomain/api/bills" $ApiBills
Invoke-Test GET "https://nfl-wallet-test.apps.$WestDomain/api/customers" $ApiCustomers
Invoke-Test GET "https://nfl-wallet-test.apps.$WestDomain/api/raiders" $ApiRaiders
Invoke-Test GET "https://webapp-nfl-wallet-test.apps.$EastDomain/"
Invoke-Test GET "https://webapp-nfl-wallet-test.apps.$WestDomain/"

# PROD (with API key)
Invoke-Test GET "https://nfl-wallet-prod.apps.$EastDomain/api/bills" $ApiBills
Invoke-Test GET "https://nfl-wallet-prod.apps.$EastDomain/api/customers" $ApiCustomers
Invoke-Test GET "https://nfl-wallet-prod.apps.$WestDomain/api/raiders" $ApiRaiders
Invoke-Test GET "https://webapp-nfl-wallet-prod.apps.$EastDomain/"
Invoke-Test GET "https://webapp-nfl-wallet-prod.apps.$WestDomain/"

Write-Host "Done (18 requests: east + west, dev/test/prod)."
