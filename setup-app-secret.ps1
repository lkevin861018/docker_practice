# Optional Compose file-backed secret preparation; PowerShell 5.1+.
[CmdletBinding()]
param()
$ErrorActionPreference = 'Stop'
Set-StrictMode -Version Latest
$dir = Join-Path $PSScriptRoot 'secrets'
New-Item -ItemType Directory -Force -Path $dir | Out-Null
$path = Join-Path $dir 'app_db_password.txt'
if (Test-Path -LiteralPath $path) { throw 'Secret already exists. To rotate it, use a coordinated database password rotation; do not blindly overwrite.' }
Write-Host 'Enter the EXISTING APP_DB_PASSWORD from .env (do not enter the admin POSTGRES_PASSWORD).'
$secure = Read-Host -Prompt 'APP_DB_PASSWORD' -AsSecureString
$bstr = [Runtime.InteropServices.Marshal]::SecureStringToBSTR($secure)
try {
    $text = [Runtime.InteropServices.Marshal]::PtrToStringBSTR($bstr)
    if ([string]::IsNullOrWhiteSpace($text)) { throw 'Secret must not be empty.' }
    [IO.File]::WriteAllText($path, $text, [Text.UTF8Encoding]::new($false))
}
finally {
    [Runtime.InteropServices.Marshal]::ZeroFreeBSTR($bstr)
}
Write-Host "Created $path" -ForegroundColor Green
Write-Host 'This file is plain text on Windows. Restrict NTFS access, never commit it, and do not share it.'
