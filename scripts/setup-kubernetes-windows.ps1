$ErrorActionPreference = 'Stop'
$toolsDir = Join-Path $env:LOCALAPPDATA 'Programs\Kubernetes'
$kind = Join-Path $toolsDir 'kind-v0.33.exe'
$kubectl = (Get-Command kubectl.exe -ErrorAction Stop).Source
$config = Join-Path (Split-Path -Parent $PSScriptRoot) 'k8s\kind-config.yaml'

if (-not (Test-Path -LiteralPath $kind -PathType Leaf)) { throw "kind is not installed: $kind" }
if (-not (Test-Path -LiteralPath $config -PathType Leaf)) { throw "kind cluster config is missing: $config" }
docker info --format '{{.OSType}}' | Out-Null
if ($LASTEXITCODE -ne 0) { throw 'Docker Desktop is not running.' }

$clusters = & $kind get clusters
if ($LASTEXITCODE -ne 0) { throw 'Could not query existing kind clusters.' }
if ($clusters -notcontains 'giai-dau') {
  & $kind create cluster --name giai-dau --config $config --wait 5m
  if ($LASTEXITCODE -ne 0) { throw 'Could not create kind cluster giai-dau.' }
} else {
  Write-Output 'kind cluster giai-dau already exists; leaving its resources unchanged.'
}

& $kubectl config use-context 'kind-giai-dau' | Out-Null
if ($LASTEXITCODE -ne 0) { throw 'Could not select Kubernetes context kind-giai-dau.' }
& $kubectl wait --for=condition=Ready node --all --timeout=180s
if ($LASTEXITCODE -ne 0) { throw 'Kubernetes node did not become Ready.' }
Write-Output 'Kubernetes is ready. App NodePort is mapped to http://localhost:8002.'
