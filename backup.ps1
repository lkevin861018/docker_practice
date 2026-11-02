# Windows PowerShell 5.1 / PowerShell 7
# PostgreSQL custom-format backup using docker compose exec + docker compose cp.
# No container ID lookup and no binary data through a PowerShell pipeline.
[CmdletBinding()]
param()

$ErrorActionPreference = 'Stop'
Set-StrictMode -Version Latest
Push-Location $PSScriptRoot
$remoteFile = $null

try {
    # Start the database and wait for its healthcheck.
    & docker compose up -d --wait db
    if ($LASTEXITCODE -ne 0) {
        throw 'PostgreSQL did not become healthy. Check: docker compose logs db'
    }

    $backupDir = Join-Path $PSScriptRoot 'backups'
    New-Item -ItemType Directory -Force -Path $backupDir | Out-Null
    $stamp = Get-Date -Format 'yyyyMMdd_HHmmss'
    $filename = 'labdb_{0}_{1}.dump' -f $stamp, ([guid]::NewGuid().ToString('N').Substring(0, 8))
    $remoteFile = '/tmp/' + $filename
    $localFile = Join-Path $backupDir $filename
    $relativeLocalFile = Join-Path (Join-Path '.' 'backups') $filename

    Write-Host 'Creating PostgreSQL custom-format backup...'
    & docker compose exec -T db sh /opt/lab/maintenance.sh backup $remoteFile
    if ($LASTEXITCODE -ne 0) {
        throw 'pg_dump or archive verification failed. Check: docker compose logs db'
    }

    # Compose service name is enough; we do NOT need docker compose ps -q db.
    $containerSource = 'db:{0}' -f $remoteFile
    & docker compose cp $containerSource $relativeLocalFile
    if ($LASTEXITCODE -ne 0) {
        throw 'docker compose cp failed.'
    }

    $item = Get-Item -LiteralPath $localFile -ErrorAction Stop
    if ($item.Length -lt 100) {
        throw 'The backup is unexpectedly small. Investigate before proceeding.'
    }
    # PostgreSQL custom-format archive starts with the PGDMP magic header.
    $stream = [System.IO.File]::OpenRead($item.FullName)
    try {
        $header = New-Object byte[] 5
        $read = $stream.Read($header, 0, $header.Length)
    } finally {
        $stream.Dispose()
    }
    if ($read -ne 5 -or [System.Text.Encoding]::ASCII.GetString($header) -ne 'PGDMP') {
        throw 'Backup file header is invalid (expected PGDMP).'
    }

    $sha = Get-FileHash -LiteralPath $item.FullName -Algorithm SHA256
    Write-Host ('BACKUP OK: {0}' -f $item.FullName) -ForegroundColor Green
    Write-Host ('SIZE: {0} bytes' -f $item.Length)
    Write-Host ('SHA256: {0}' -f $sha.Hash)
} finally {
    if (-not [string]::IsNullOrWhiteSpace($remoteFile)) {
        try {
            & docker compose exec -T db rm -f $remoteFile 2>$null | Out-Null
        } catch {
            Write-Warning 'Could not clean up the temporary file inside the database container.'
        }
    }
    Pop-Location
}
