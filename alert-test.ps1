# PowerShell 5.1+; a safe synthetic alert (no service is stopped).
[CmdletBinding()]
param([string]$AlertmanagerPort = '9093')
$ErrorActionPreference = 'Stop'
$start = (Get-Date).ToUniversalTime()
$alert = @{
  labels = @{
    alertname = 'DockerLabManualTest'
    severity = 'warning'
    job = 'manual-test'
    instance = 'windows11-lab'
  }
  annotations = @{
    summary = 'Manual notification test (no real failure)'
    description = 'Submitted from alert-test.ps1 to test Alertmanager and Mailpit.'
  }
  startsAt = $start.ToString('o')
  endsAt = $start.AddMinutes(2).ToString('o')
}
$payload = ConvertTo-Json -InputObject @($alert) -Depth 8 -Compress
$endpoint = "http://127.0.0.1:$AlertmanagerPort/api/v2/alerts"
Invoke-RestMethod -Method Post -Uri $endpoint -ContentType 'application/json' -Body $payload -TimeoutSec 20 | Out-Null
Write-Host "PASS: synthetic alert accepted by $endpoint" -ForegroundColor Green
Write-Host 'Open Mailpit at http://localhost:8025 after about 10-30 seconds.'
Write-Host 'This is a test alert and will automatically expire (about 2 minutes).'
