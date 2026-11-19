$ErrorActionPreference = 'Stop'
$kubectl = (Get-Command kubectl.exe -ErrorAction Stop).Source

$statusOutput = docker desktop kubernetes status 2>&1
$statusCode = $LASTEXITCODE
$status = $statusOutput | Out-String
if ($statusCode -ne 0 -or $status -notmatch '(?m)^State:\s+running\s*$') {
  throw "Docker Desktop Kubernetes is not running. Open Docker Desktop > Kubernetes and start/create the cluster.`n$status"
}

& $kubectl config use-context 'docker-desktop' | Out-Null
if ($LASTEXITCODE -ne 0) { throw 'Could not select Kubernetes context docker-desktop.' }
& $kubectl wait --for=condition=Ready node --all --timeout=180s
if ($LASTEXITCODE -ne 0) { throw 'Kubernetes node did not become Ready.' }
Write-Output 'Docker Desktop Kubernetes is ready. App Service uses port 8002.'
