# Verify Docker Lab v6 app hardening and basic HTTP functionality.
[CmdletBinding()]
param()
$ErrorActionPreference = 'Stop'
Set-StrictMode -Version Latest
Push-Location $PSScriptRoot
try {
    $jsonText = (& docker compose config --format json) -join "`n"
    if ($LASTEXITCODE -ne 0) { throw 'docker compose config failed' }
    $config = $jsonText | ConvertFrom-Json
    $service = $config.services.app
    if ($service.read_only -ne $true) { throw 'app is not configured read_only=true' }
    if (@($service.cap_drop) -notcontains 'ALL') { throw 'app does not drop ALL capabilities' }
    if (@($service.security_opt) -notcontains 'no-new-privileges:true') { throw 'app missing no-new-privileges' }
    Write-Host 'PASS: Compose hardening configuration' -ForegroundColor Green

    & docker compose exec -T app python security_verify.py
    if ($LASTEXITCODE -ne 0) { throw 'Running container does not meet expected hardening settings; recreate app.' }
    Write-Host 'PASS: non-root app & read-only application filesystem' -ForegroundColor Green

    $response = Invoke-RestMethod -Uri 'http://localhost:8080/healthz' -TimeoutSec 20
    if ($response.status -ne 'ok' -or $response.database -ne 'connected') { throw 'Flask or DB health check failed' }
    Write-Host 'PASS: Flask/PostgreSQL HTTP health check' -ForegroundColor Green
}
finally { Pop-Location }
