param(
  [Parameter(Mandatory = $true)] [string]$Image,
  [Parameter(Mandatory = $true)] [string]$SourceDir,
  [Parameter(Mandatory = $true)] [string]$DeployDir,
  [string]$Namespace = 'giai-dau',
  [string]$Deployment = 'giai-dau-app',
  [string]$Container = 'app',
  [int]$TimeoutSeconds = 180
)

$ErrorActionPreference = 'Stop'
$SourceDir = [System.IO.Path]::GetFullPath($SourceDir)
$DeployDir = [System.IO.Path]::GetFullPath($DeployDir)
$kindPath = Join-Path $env:LOCALAPPDATA 'Programs\Kubernetes\kind-v0.33.exe'
$kind = if (Test-Path -LiteralPath $kindPath) { $kindPath } else { (Get-Command kind.exe -ErrorAction Stop).Source }
$kubectl = (Get-Command kubectl.exe -ErrorAction Stop).Source
$docker = (Get-Command docker.exe -ErrorAction Stop).Source
$envFile = Join-Path $DeployDir '.env'
$namespaceFile = Join-Path $SourceDir 'k8s\namespace.yaml'
$appFile = Join-Path $SourceDir 'k8s\app.yaml'
$imageTag = 'giai-dau-app:IMAGE_PLACEHOLDER'
$dbContainer = 'giai-dau-db'
$dbService = 'giai-dau-db'
$composeNetwork = 'kind'

foreach ($file in @($envFile, $namespaceFile, $appFile)) {
  if (-not (Test-Path -LiteralPath $file -PathType Leaf)) { throw "Required file is missing: $file" }
}

# Use the local kind cluster created for this project; Compose remains the default deployment target.
& $kind get clusters | Out-Null
if ($LASTEXITCODE -ne 0) { throw 'Could not query kind clusters.' }
$clusters = & $kind get clusters
if ($LASTEXITCODE -ne 0 -or $clusters -notcontains 'giai-dau') {
  throw "kind cluster 'giai-dau' is not available. Run scripts\setup-kubernetes-windows.ps1 first."
}
& $kubectl config use-context 'kind-giai-dau' | Out-Null
if ($LASTEXITCODE -ne 0) { throw 'Could not select Kubernetes context kind-giai-dau.' }
& $kubectl get nodes --request-timeout='15s' | Out-Null
if ($LASTEXITCODE -ne 0) { throw 'Kubernetes cluster is unavailable.' }

# Keep database private: attach its existing Compose container to kind's internal Docker network.
$dbHealth = & $docker inspect $dbContainer --format '{{.State.Health.Status}}' 2>$null
if ($LASTEXITCODE -ne 0 -or $dbHealth.Trim() -ne 'healthy') { throw 'The existing PostgreSQL container is not healthy.' }
$dbObject = (& $docker inspect $dbContainer | ConvertFrom-Json)[0]
$dbNetwork = $dbObject.NetworkSettings.Networks.PSObject.Properties[$composeNetwork].Value
if (-not $dbNetwork) {
  & $docker network connect --alias $dbService $composeNetwork $dbContainer
  if ($LASTEXITCODE -ne 0) {
    # A concurrently completed attachment is safe; verify it below before proceeding.
    $attachedObject = (& $docker inspect $dbContainer | ConvertFrom-Json)[0]
    $dbNetwork = $attachedObject.NetworkSettings.Networks.PSObject.Properties[$composeNetwork].Value
    if (-not $dbNetwork) { throw 'Could not attach PostgreSQL to the kind Docker network.' }
  } else {
    $dbObject = (& $docker inspect $dbContainer | ConvertFrom-Json)[0]
    $dbNetwork = $dbObject.NetworkSettings.Networks.PSObject.Properties[$composeNetwork].Value
  }
}
$dbIp = $dbNetwork.IPAddress
if (-not $dbIp) { throw 'Could not determine PostgreSQL IP on the kind network.' }

# Read the already-provisioned Compose .env without printing its credentials.
$settings = @{}
foreach ($line in Get-Content -LiteralPath $envFile -Encoding UTF8) {
  if ($line -match '^\s*([A-Za-z_][A-Za-z0-9_]*)\s*=\s*(.*?)\s*$') {
    $value = $Matches[2].Trim()
    if (($value.StartsWith('"') -and $value.EndsWith('"')) -or ($value.StartsWith("'") -and $value.EndsWith("'"))) {
      $value = $value.Substring(1, $value.Length - 2)
    }
    $settings[$Matches[1]] = $value
  }
}
foreach ($key in @('POSTGRES_USER', 'POSTGRES_DB', 'POSTGRES_PASSWORD_URL_ENCODED')) {
  if (-not $settings[$key]) { throw "Missing $key in $envFile." }
}
$databaseUrl = "postgresql://$($settings.POSTGRES_USER):$($settings.POSTGRES_PASSWORD_URL_ENCODED)@$dbService.$Namespace.svc.cluster.local:5432/$($settings.POSTGRES_DB)"

# Create/refresh the service endpoint and DB Secret from local state; the secret manifest is temporary and ignored by Git.
$namespaceResult = & $kubectl apply -f (Join-Path $SourceDir 'k8s\namespace.yaml') 2>&1
if ($LASTEXITCODE -ne 0) { throw "Could not apply Kubernetes namespace: $namespaceResult" }
$encodedDatabaseUrl = [Convert]::ToBase64String([Text.Encoding]::UTF8.GetBytes($databaseUrl))
$secretYaml = @"
apiVersion: v1
kind: Secret
metadata:
  name: giai-dau-db
  namespace: $Namespace
type: Opaque
data:
  DATABASE_URL: $encodedDatabaseUrl
"@
$databaseResources = @"
apiVersion: v1
kind: Service
metadata:
  name: $dbService
  namespace: $Namespace
spec:
  ports:
    - name: postgres
      port: 5432
      targetPort: 5432
      protocol: TCP
---
apiVersion: discovery.k8s.io/v1
kind: EndpointSlice
metadata:
  name: giai-dau-db-1
  namespace: $Namespace
  labels:
    kubernetes.io/service-name: $dbService
    endpointslice.kubernetes.io/managed-by: manual
addressType: IPv4
ports:
  - name: postgres
    port: 5432
    protocol: TCP
endpoints:
  - addresses:
      - $dbIp
    conditions:
      ready: true
"@
$tempSecret = Join-Path $env:TEMP "giai-dau-db-secret-$PID.yaml"
$tempDbResources = Join-Path $env:TEMP "giai-dau-db-endpoint-$PID.yaml"
try {
  Set-Content -LiteralPath $tempSecret -Value $secretYaml -Encoding UTF8
  Set-Content -LiteralPath $tempDbResources -Value $databaseResources -Encoding UTF8
  & $kubectl apply -f $tempSecret | Out-Null
  if ($LASTEXITCODE -ne 0) { throw 'Could not apply database Secret.' }
  & $kubectl apply -f $tempDbResources | Out-Null
  if ($LASTEXITCODE -ne 0) { throw 'Could not configure the private PostgreSQL service endpoint.' }
} finally {
  Remove-Item -LiteralPath $tempSecret, $tempDbResources -Force -ErrorAction SilentlyContinue
}

# Load the locally built image into kind, then apply the exact commit image to the Deployment.
& $kind load docker-image $Image --name giai-dau
if ($LASTEXITCODE -ne 0) { throw "Could not load local image into kind: $Image" }
$deploymentsJson = & $kubectl get deployments --namespace $Namespace -o json
$deploymentsExitCode = $LASTEXITCODE
$oldRevision = $null
if ($deploymentsExitCode -eq 0 -and $deploymentsJson) {
  $oldDeployment = ($deploymentsJson | ConvertFrom-Json).items | Where-Object { $_.metadata.name -eq $Deployment } | Select-Object -First 1
  if ($oldDeployment) { $oldRevision = $oldDeployment.metadata.annotations['deployment.kubernetes.io/revision'] }
}
$appYaml = (Get-Content -LiteralPath $appFile -Raw -Encoding UTF8).Replace($imageTag, $Image)
if ($appYaml -eq (Get-Content -LiteralPath $appFile -Raw -Encoding UTF8)) { throw 'Kubernetes app manifest image placeholder is missing.' }
$tempApp = Join-Path $env:TEMP "giai-dau-app-$PID.yaml"
try {
  Set-Content -LiteralPath $tempApp -Value $appYaml -Encoding UTF8
  $applyResult = & $kubectl apply -f $tempApp 2>&1
  if ($LASTEXITCODE -ne 0) { throw "Could not apply the Kubernetes app Deployment and Service: $applyResult" }
  & $kubectl rollout status "deployment/$Deployment" --namespace $Namespace "--timeout=${TimeoutSeconds}s"
  if ($LASTEXITCODE -ne 0) { throw "Kubernetes rollout did not complete within ${TimeoutSeconds} seconds." }
  Write-Output "Kubernetes deployment succeeded: $Deployment uses $Image. App URL: http://localhost:8002/giai-dau.html"
} catch {
  $deploymentError = $_
  $currentDeployments = & $kubectl get deployments --namespace $Namespace -o json 2>$null
  $currentQueryCode = $LASTEXITCODE
  $currentRevision = $null
  if ($currentQueryCode -eq 0 -and $currentDeployments) {
    $currentDeployment = ($currentDeployments | ConvertFrom-Json).items | Where-Object { $_.metadata.name -eq $Deployment } | Select-Object -First 1
    if ($currentDeployment) { $currentRevision = $currentDeployment.metadata.annotations['deployment.kubernetes.io/revision'] }
  }
  if ($oldRevision -and $currentRevision -and [int]$currentRevision -gt [int]$oldRevision) {
    & $kubectl rollout undo "deployment/$Deployment" --namespace $Namespace "--to-revision=$oldRevision"
    if ($LASTEXITCODE -ne 0) { throw "Rollout failed and rollback to revision $oldRevision also failed: $deploymentError" }
    & $kubectl rollout status "deployment/$Deployment" --namespace $Namespace "--timeout=${TimeoutSeconds}s"
    if ($LASTEXITCODE -ne 0) { throw "Rollback to revision $oldRevision was requested, but the previous version is not ready: $deploymentError" }
    throw "Rollout failed; revision $oldRevision was restored and is ready. $deploymentError"
  }
  throw "Initial Kubernetes deployment failed and no previous Deployment revision exists. $deploymentError"
} finally {
  Remove-Item -LiteralPath $tempApp -Force -ErrorAction SilentlyContinue
}
