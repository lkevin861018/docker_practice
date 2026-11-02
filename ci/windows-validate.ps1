# Safe local preflight; runs no image publishing, database resets or remote deployment.
[CmdletBinding()]
param()
$ErrorActionPreference = 'Stop'
Set-StrictMode -Version Latest
$root = Split-Path -Parent $PSScriptRoot
Push-Location $root
try {
    & docker version --format '{{.Server.Version}}'
    if ($LASTEXITCODE -ne 0) { throw 'Docker Engine is unavailable.' }
    if (-not (Test-Path .env)) { throw 'Missing .env. Keep the existing local .env.' }
    & docker compose config --quiet
    if ($LASTEXITCODE -ne 0) { throw 'Compose configuration validation failed.' }
    & docker compose ps
    if ($LASTEXITCODE -ne 0) { throw 'Compose status query failed.' }
    Write-Host 'PASS: Docker, Compose syntax and service status query' -ForegroundColor Green
    Write-Host 'Unit tests and CI security gate run in GitHub Actions; no remote deployment occurred.'
} finally {
    Pop-Location
}
