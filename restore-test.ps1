# Restore a PostgreSQL custom-format backup into a NEW test database.
# Does not depend on a Docker container ID.
[CmdletBinding()]
param(
    [Parameter(Mandatory = $true)]
    [string]$BackupFile,
    [ValidatePattern('^labdb_restore_[a-z0-9_]+$')]
    [string]$TargetDatabase = 'labdb_restore_test'
)

$ErrorActionPreference = 'Stop'
Set-StrictMode -Version Latest
Push-Location $PSScriptRoot
$remoteFile = $null
try {
    $file = (Resolve-Path -LiteralPath $BackupFile -ErrorAction Stop).Path

    & docker compose up -d --wait db
    if ($LASTEXITCODE -ne 0) { throw 'Database is not healthy.' }

    $currentDb = (& docker compose exec -T db printenv POSTGRES_DB | Out-String).Trim()
    if ($LASTEXITCODE -ne 0 -or [string]::IsNullOrWhiteSpace($currentDb)) {
        throw 'Cannot read POSTGRES_DB.'
    }
    if ($TargetDatabase -eq $currentDb) {
        throw 'Refusing to restore into the live application database.'
    }

    $remoteFile = '/tmp/restore_' + [guid]::NewGuid().ToString('N') + '.dump'
    $containerDestination = 'db:{0}' -f $remoteFile
    & docker compose cp $file $containerDestination
    if ($LASTEXITCODE -ne 0) { throw 'Cannot copy backup file into database service.' }

    Write-Host ('Checking archive and creating test database: {0}' -f $TargetDatabase)
    & docker compose exec -T db sh /opt/lab/maintenance.sh create-test $TargetDatabase $remoteFile
    if ($LASTEXITCODE -ne 0) {
        throw 'Archive invalid or target database already exists. Existing databases were not overwritten.'
    }

    & docker compose exec -T db sh /opt/lab/maintenance.sh restore-test $TargetDatabase $remoteFile
    if ($LASTEXITCODE -ne 0) {
        throw 'Restore failed; test database may exist, and should be inspected before retrying.'
    }

    Write-Host 'Restored rows in public.visits:'
    & docker compose exec -T db sh /opt/lab/maintenance.sh count $TargetDatabase
    if ($LASTEXITCODE -ne 0) { throw 'Restore succeeded but row-count validation failed.' }
    Write-Host ('RESTORE OK: {0} (original application database unchanged)' -f $TargetDatabase) -ForegroundColor Green
} finally {
    if (-not [string]::IsNullOrWhiteSpace($remoteFile)) {
        try {
            & docker compose exec -T db rm -f $remoteFile 2>$null | Out-Null
        } catch {
            Write-Warning 'Could not clean up temporary archive in the container.'
        }
    }
    Pop-Location
}
