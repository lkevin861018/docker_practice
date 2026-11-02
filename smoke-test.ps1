# Windows PowerShell 5.1 / PowerShell 7 compatible.
param(
    [string]$BaseUrl = 'http://localhost:8080',
    [string]$PgAdminUrl = 'http://localhost:5050'
)
$ErrorActionPreference = 'Stop'
function Assert-True($Condition, $Message) {
    if (-not $Condition) { throw "FAILED: $Message" }
    Write-Host "PASS: $Message" -ForegroundColor Green
}

Write-Host "Testing $BaseUrl" -ForegroundColor Cyan
$health = Invoke-RestMethod -Method Get -Uri "$BaseUrl/healthz" -TimeoutSec 15
Assert-True ($health.status -eq 'ok' -and $health.database -eq 'connected') 'Flask and database health'

$html = Invoke-WebRequest -Method Get -Uri "$BaseUrl/" -UseBasicParsing -TimeoutSec 15
Assert-True ($html.StatusCode -eq 200 -and $html.Content -match 'Docker') 'Nginx forwards the home page'

$visitor = 'SmokeTest-' + [guid]::NewGuid().ToString('N').Substring(0, 8)
$payload = @{ visitor = $visitor } | ConvertTo-Json -Compress
$bytes = [System.Text.Encoding]::UTF8.GetBytes($payload)
$created = Invoke-RestMethod -Method Post -Uri "$BaseUrl/api/visits" -ContentType 'application/json; charset=utf-8' -Body $bytes -TimeoutSec 15
Assert-True ($created.id -gt 0 -and $created.visitor -eq $visitor) 'POST inserts a row into PostgreSQL'

$visits = Invoke-RestMethod -Method Get -Uri "$BaseUrl/api/visits" -TimeoutSec 15
$matching = @($visits.items | Where-Object { $_.id -eq $created.id -and $_.visitor -eq $visitor })
Assert-True ($matching.Count -eq 1) 'GET retrieves the inserted row'

$adminPage = Invoke-WebRequest -Method Get -Uri "$PgAdminUrl/login" -UseBasicParsing -TimeoutSec 30
Assert-True ($adminPage.StatusCode -eq 200 -and $adminPage.Content -match 'pgAdmin') 'pgAdmin login page is accessible'

Write-Host "All tests passed. Inserted visitor: $visitor" -ForegroundColor Cyan
