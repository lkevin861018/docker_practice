# Run from project directory after Docker Compose services started.
[CmdletBinding()]
param()
$ErrorActionPreference = 'Stop'
Set-StrictMode -Version Latest
Push-Location $PSScriptRoot
try {
  & docker compose ps
  if ($LASTEXITCODE -ne 0) { throw 'Docker Compose is unavailable' }
  $envFile = Join-Path $PSScriptRoot '.env'
  $vals = @{}
  foreach ($line in (Get-Content -LiteralPath $envFile)) {
    if ($line -match '^([A-Z][A-Z0-9_]*)=(.*)$') { $vals[$Matches[1]]=$Matches[2] }
  }
  $pport = if ($vals.ContainsKey('PROMETHEUS_PORT')) { $vals['PROMETHEUS_PORT'] } else { '9090' }
  $gport = if ($vals.ContainsKey('GRAFANA_PORT')) { $vals['GRAFANA_PORT'] } else { '3000' }
  $result = Invoke-RestMethod -Uri "http://localhost:$pport/api/v1/targets" -TimeoutSec 20
  if ($result.status -ne 'success') { throw 'Prometheus targets API did not report success' }
  $targets = @($result.data.activeTargets)
  foreach ($job in @('prometheus','flask','nginx','postgres','http-probe')) {
    $subset = @($targets | Where-Object { $_.labels.job -eq $job })
    if ($subset.Count -eq 0) { throw "Missing Prometheus job: $job" }
    foreach ($target in $subset) {
      Write-Host ("{0} {1}: {2}" -f $job, $target.labels.instance, $target.health)
      if ($target.health -ne 'up') { throw "Scrape not healthy: $job" }
    }
  }
  $probes = Invoke-RestMethod -Uri "http://localhost:$pport/api/v1/query?query=probe_success" -TimeoutSec 20
  foreach ($res in @($probes.data.result)) {
    if ([double]$res.value[1] -ne 1) { throw ('HTTP probe failed: ' + $res.metric.instance) }
  }
  $grafana = Invoke-RestMethod -Uri "http://localhost:$gport/api/health" -TimeoutSec 20
  if ($grafana.database -ne 'ok') { throw 'Grafana database health not OK' }
  Write-Host 'PASS: all monitoring checks succeeded' -ForegroundColor Green
} finally { Pop-Location }
