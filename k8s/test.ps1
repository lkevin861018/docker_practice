[CmdletBinding()]
param([string]$BaseUrl = 'http://localhost:18088')
$ErrorActionPreference='Stop'
Set-StrictMode -Version Latest
$health=Invoke-RestMethod "$BaseUrl/healthz"
if ($health.status -ne 'ok' -or $health.database -ne 'connected') { throw 'Health check failed' }
Write-Host 'PASS: healthz + PostgreSQL'
$visitor='k8s-smoke-'+[Guid]::NewGuid().ToString('N').Substring(0,8)
$payload = @{visitor=$visitor}| ConvertTo-Json -Compress
$response=Invoke-RestMethod -Method Post -Uri "$BaseUrl/api/visits" -ContentType 'application/json' -Body $payload
if ($response.visitor -ne $visitor) { throw 'POST returned unexpected data' }
Write-Host 'PASS: insert'
$items=Invoke-RestMethod "$BaseUrl/api/visits"
if (@($items.items | Where-Object { $_.visitor -eq $visitor }).Count -ne 1) { throw 'Inserted data not returned in GET' }
Write-Host 'PASS: query'
Write-Host 'All smoke tests passed.'
