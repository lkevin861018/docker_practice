[CmdletBinding()]
param()
$ErrorActionPreference = 'Stop'
Set-StrictMode -Version Latest
$here = Split-Path -Parent $MyInvocation.MyCommand.Path
$namespace = 'docker-k8s-lab'
$context = (& kubectl config current-context).Trim()
if ($LASTEXITCODE -ne 0 -or $context -ne 'docker-desktop') {
    throw "Switch Kubernetes context to docker-desktop first. Current: $context"
}
function Run-Kubectl([string[]]$Arguments) {
    & kubectl @Arguments
    if ($LASTEXITCODE -ne 0) { throw "kubectl command failed: $($Arguments -join ' ')" }
}
& (Join-Path $here 'setup-secrets.ps1')
if ($LASTEXITCODE -ne 0) { throw 'Secret setup failed' }
Run-Kubectl -Arguments @('apply', '-f', (Join-Path $here '10-configmaps.yaml'))
Run-Kubectl -Arguments @('apply', '-f', (Join-Path $here '20-postgres.yaml'))
Run-Kubectl -Arguments @('rollout', 'status', '-n', $namespace, 'statefulset/db', '--timeout=240s')
Run-Kubectl -Arguments @('apply', '-f', (Join-Path $here '25-db-setup-job.yaml'))
Run-Kubectl -Arguments @('wait', '-n', $namespace, '--for=condition=complete', 'job/role-setup', '--timeout=180s')
Run-Kubectl -Arguments @('apply', '-f', (Join-Path $here '30-flask.yaml'))
Run-Kubectl -Arguments @('rollout', 'status', '-n', $namespace, 'deployment/flask', '--timeout=180s')
Run-Kubectl -Arguments @('apply', '-f', (Join-Path $here '40-nginx.yaml'))
Run-Kubectl -Arguments @('rollout', 'status', '-n', $namespace, 'deployment/nginx', '--timeout=180s')
Run-Kubectl -Arguments @('get', '-n', $namespace, 'pods,svc,pvc')
Write-Host 'Ready. Run: kubectl -n docker-k8s-lab port-forward service/nginx 18088:80'
