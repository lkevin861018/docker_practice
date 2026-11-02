# Docker Lab v6: Trivy scan without mounting the Docker socket into the scanner.
# Windows PowerShell 5.1 / PowerShell 7. Requires Docker Desktop and network access for Trivy DB updates.
[CmdletBinding()]
param(
    [ValidateNotNullOrEmpty()]
    [string]$Services = 'app,nginx,db',
    [switch]$FailOnCritical
)
$ErrorActionPreference = 'Stop'
Set-StrictMode -Version Latest
Push-Location $PSScriptRoot
try {
    $images = @{
        'app' = 'flask-nginx-postgres-lab-app:v6'
        'nginx' = 'nginx:stable-alpine'
        'db' = 'postgres:17-alpine'
        'pgadmin' = 'dpage/pgadmin4:9.19'
        'prometheus' = 'prom/prometheus:v3.13.3'
        'grafana' = 'grafana/grafana:13.3.0'
        'alertmanager' = 'prom/alertmanager:v0.34.2'
        'postgres-exporter' = 'quay.io/prometheuscommunity/postgres-exporter:v0.20.1'
    }
    $scannerImage = 'aquasec/trivy:0.76.0'
    $cacheVolume = 'docker-lab-trivy-cache'
    $reportDir = Join-Path $PSScriptRoot ('reports\trivy\' + (Get-Date -Format 'yyyyMMdd-HHmmss'))
    New-Item -ItemType Directory -Path $reportDir -Force | Out-Null

    & docker info --format '{{.ServerVersion}}' | Out-Null
    if ($LASTEXITCODE -ne 0) { throw 'Docker Engine unavailable. Start Docker Desktop.' }
    & docker volume create $cacheVolume | Out-Null
    if ($LASTEXITCODE -ne 0) { throw 'Could not create Trivy cache volume.' }
    & docker pull $scannerImage
    if ($LASTEXITCODE -ne 0) { throw 'Failed to download pinned Trivy scanner image.' }

    # Scan only copied configuration files, not .env or local secret files.
    $configDir = Join-Path $reportDir 'config-input'
    New-Item -ItemType Directory -Path $configDir -Force | Out-Null
    Copy-Item (Join-Path $PSScriptRoot 'compose.yaml') (Join-Path $configDir 'compose.yaml')
    Copy-Item (Join-Path $PSScriptRoot 'app\Dockerfile') (Join-Path $configDir 'Dockerfile')
    $configBind = "type=bind,source=$reportDir,target=/scan"
    $cacheMount = "type=volume,source=$cacheVolume,target=/root/.cache"
    Write-Host 'Scanning Compose and Dockerfile misconfigurations...' -ForegroundColor Cyan
    & docker run --rm --mount $configBind --mount $cacheMount $scannerImage config `
        --format json --output /scan/config-findings.json /scan/config-input
    if ($LASTEXITCODE -ne 0) { throw 'Trivy config scan failed' }

    $totalHigh = 0
    $totalCritical = 0
    foreach ($service in @($Services -split '\s*,\s*')) {
        if (-not $images.ContainsKey($service)) { throw "Unknown service name: $service" }
        $image = $images[$service]
        Write-Host "`nScanning service '$service' image '$image'" -ForegroundColor Cyan
        & docker image inspect $image --format '{{.Id}}' | Out-Null
        if ($LASTEXITCODE -ne 0) {
            throw "Image not found locally: $image. Try: docker compose build app; docker compose pull"
        }

        $archiveName = 'image.tar'
        $archive = Join-Path $reportDir $archiveName
        try {
            & docker image save --output $archive $image
            if ($LASTEXITCODE -ne 0) { throw "Could not save $image" }

            $bind = "type=bind,source=$reportDir,target=/scan"
            $cache = "type=volume,source=$cacheVolume,target=/root/.cache"
            $vulnOut = "/scan/$service-vulnerabilities.json"
            & docker run --rm --mount $bind --mount $cache $scannerImage image `
                --input "/scan/$archiveName" --scanners vuln --severity HIGH,CRITICAL `
                --format json --output $vulnOut
            if ($LASTEXITCODE -ne 0) { throw "Trivy vulnerability scan failed for $service" }

            & docker run --rm --mount $bind --mount $cache $scannerImage image `
                --input "/scan/$archiveName" --format cyclonedx --output "/scan/$service-sbom.cdx.json"
            if ($LASTEXITCODE -ne 0) { throw "Trivy SBOM generation failed for $service" }

            $report = Get-Content -LiteralPath (Join-Path $reportDir "$service-vulnerabilities.json") -Raw | ConvertFrom-Json
            $high = 0
            $critical = 0
            if ($null -ne $report.Results) {
                foreach ($result in @($report.Results)) {
                    if ($null -ne $result -and $null -ne $result.Vulnerabilities) {
                        foreach ($v in @($result.Vulnerabilities)) {
                            if ($null -ne $v) {
                                if ($v.Severity -eq 'HIGH') { $high++ }
                                if ($v.Severity -eq 'CRITICAL') { $critical++ }
                            }
                        }
                    }
                }
            }
            $totalHigh += $high
            $totalCritical += $critical
            Write-Host "[$service] HIGH=$high CRITICAL=$critical" -ForegroundColor Yellow
        }
        finally {
            if (Test-Path -LiteralPath $archive) { Remove-Item -LiteralPath $archive -Force }
        }
    }
    Write-Host "`nReports: $reportDir" -ForegroundColor Green
    Write-Host "Total findings: HIGH=$totalHigh CRITICAL=$totalCritical"
    Write-Host 'Findings are package vulnerability matches, NOT proof of exploitation. Review fix versions and exposure.'
    if ($FailOnCritical -and $totalCritical -gt 0) { throw "Critical findings detected: $totalCritical" }
}
finally {
    Pop-Location
}
