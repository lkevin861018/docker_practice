# Checks local Alertmanager and Mailpit endpoints (Windows PowerShell 5.1+).
[CmdletBinding()]
param([string]$AlertmanagerPort = '9093', [string]$MailpitPort = '8025')
$ErrorActionPreference = 'Stop'
$ready = Invoke-WebRequest -UseBasicParsing -Uri "http://127.0.0.1:$AlertmanagerPort/-/ready" -TimeoutSec 15
if ($ready.StatusCode -ne 200) { throw 'Alertmanager is not ready' }
$state = Invoke-RestMethod -Uri "http://127.0.0.1:$AlertmanagerPort/api/v2/status" -TimeoutSec 15
if (-not $state.config) { throw 'Alertmanager configuration is not available' }
$messages = Invoke-RestMethod -Uri "http://127.0.0.1:$MailpitPort/api/v1/messages" -TimeoutSec 15
Write-Host 'PASS: Alertmanager ready; API and Mailpit reachable' -ForegroundColor Green
Write-Host ("Mailpit captured messages: {0}" -f $messages.messages_count)
Write-Host 'Prometheus: http://localhost:9090/status or http://localhost:9090/alerts'
