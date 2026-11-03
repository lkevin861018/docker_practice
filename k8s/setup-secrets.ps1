[CmdletBinding()]
param()
$ErrorActionPreference = 'Stop'
Set-StrictMode -Version Latest
$here = Split-Path -Parent $MyInvocation.MyCommand.Path
$namespace = 'docker-k8s-lab'
$context = (& kubectl config current-context).Trim()
if ($LASTEXITCODE -ne 0 -or $context -ne 'docker-desktop') {
    throw "Expected Kubernetes context docker-desktop; currently '$context'. Switch with kubectl config use-context docker-desktop."
}
& kubectl apply -f (Join-Path $here '00-namespace.yaml')
if ($LASTEXITCODE -ne 0) { throw 'Namespace creation failed' }
$found = (& kubectl -n $namespace get secret lab-db-secret --ignore-not-found -o name)
if ($LASTEXITCODE -ne 0) { throw 'Could not query Kubernetes secrets' }
if (-not [string]::IsNullOrWhiteSpace(($found -join ''))) {
    Write-Host 'Secret lab-db-secret already exists; leaving credentials unchanged.'
    exit 0
}
function New-RandomPassword {
    $bytes = New-Object byte[] 32
    $rng = [System.Security.Cryptography.RandomNumberGenerator]::Create()
    try { $rng.GetBytes($bytes) } finally { $rng.Dispose() }
    return [Convert]::ToBase64String($bytes)
}
function Encode-Secret([string]$value) {
    return [Convert]::ToBase64String([System.Text.Encoding]::UTF8.GetBytes($value))
}
$a = Encode-Secret (New-RandomPassword)
$b = Encode-Secret (New-RandomPassword)
$c = Encode-Secret (New-RandomPassword)
$d = Encode-Secret (New-RandomPassword)
$tempPath = Join-Path $here '.secret.generated.yaml'
$manifest = @"
apiVersion: v1
kind: Secret
metadata:
  name: lab-db-secret
  namespace: docker-k8s-lab
type: Opaque
data:
  DB_ADMIN_PASSWORD: $a
  APP_DB_PASSWORD: $b
  REPORT_DB_PASSWORD: $c
  METRICS_DB_PASSWORD: $d
"@
try {
    [System.IO.File]::WriteAllText($tempPath, $manifest, [System.Text.UTF8Encoding]::new($false))
    & kubectl apply -f $tempPath
    if ($LASTEXITCODE -ne 0) { throw 'Could not create Kubernetes Secret' }
    Write-Host 'Created lab-db-secret. Values are stored only in Kubernetes for this local lab.'
} finally {
    Remove-Item -LiteralPath $tempPath -Force -ErrorAction SilentlyContinue
}
