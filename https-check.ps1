# Check v8 HTTPS environment from Windows PowerShell 5.1 or PowerShell 7.
[CmdletBinding()]
param([string]$Domain)
$ErrorActionPreference = 'Stop'
Set-StrictMode -Version Latest
Push-Location $PSScriptRoot
try {
    if (!(Test-Path .\caddy\Caddyfile)) { throw 'Missing caddy/Caddyfile. Copy Caddyfile.example and insert your real bcrypt hash.' }
    if ((Get-Content .\caddy\Caddyfile -Raw).Contains('REPLACE_WITH_BCRYPT_HASH')) { throw 'Replace the bcrypt placeholder in caddy/Caddyfile first.' }

    & docker compose -f compose.yaml -f compose.public.yaml config --quiet
    if ($LASTEXITCODE -ne 0) { throw 'Docker Compose config failed.' }
    Write-Host 'PASS: Compose configuration' -ForegroundColor Green

    & docker compose -f compose.yaml -f compose.public.yaml ps caddy nginx app db
    if ($LASTEXITCODE -ne 0) { throw 'Cannot inspect containers.' }

    if (-not $Domain) {
       $line = Get-Content .\.env -ErrorAction Stop | Where-Object { $_ -match '^\s*SITE_DOMAIN\s*=' } | Select-Object -Last 1
       if ($line) { $Domain = (($line -split '=',2)[1]).Trim().Trim('"').Trim("'") }
    }
    if (-not $Domain -or $Domain -match 'example\.com$') { throw 'Provide a real hostname in .env or use -Domain your.example.com.' }

    Write-Host "Checking DNS for $Domain ..."
    try { Resolve-DnsName -Name $Domain -Type A -ErrorAction Stop | Where-Object IPAddress | Select-Object Name,IPAddress }
    catch { Write-Warning "DNS resolution failed: $($_.Exception.Message)" }

    Write-Host 'Expected HTTP response: 401 Unauthorized (because demo requires basic_auth).' -ForegroundColor Cyan
    & curl.exe --silent --show-error --head --max-time 20 "https://$Domain/"
    if ($LASTEXITCODE -ne 0) { Write-Warning 'HTTPS request failed: inspect DNS, port 80/443, certificate and Caddy logs.' }

    Write-Host 'Inspect logs: docker compose -f compose.yaml -f compose.public.yaml logs --tail=100 caddy'
}
finally { Pop-Location }
