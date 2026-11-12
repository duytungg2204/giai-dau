param(
  [Parameter(Mandatory = $true)]
  [string]$SourceDir,

  [Parameter(Mandatory = $true)]
  [string]$DeployDir,

  [Parameter(Mandatory = $true)]
  [string]$Image
)

$ErrorActionPreference = 'Stop'
$SourceDir = [System.IO.Path]::GetFullPath($SourceDir)
$DeployDir = [System.IO.Path]::GetFullPath($DeployDir)
$composeFile = Join-Path $SourceDir 'docker-compose.yml'
$envFile = Join-Path $DeployDir '.env'
$docker = (Get-Command docker.exe -ErrorAction Stop).Source
$containerName = 'giai-dau-app'
$databaseContainer = 'giai-dau-db'
$deployTag = 'giai-dau-app:deploy'
$rollbackTag = 'giai-dau-app:rollback'
$composeArgs = @(
  'compose', '--env-file', $envFile,
  '--project-directory', $DeployDir,
  '--project-name', 'cuoikytkpm-main',
  '--file', $composeFile
)

foreach ($file in @($composeFile, $envFile)) {
  if (-not (Test-Path -LiteralPath $file -PathType Leaf)) {
    throw "Required deployment file is missing: $file"
  }
}

$composeText = Get-Content -LiteralPath $composeFile -Raw
if ($composeText -notmatch '(?m)^\s*image:\s*giai-dau-app:deploy\s*$') {
  throw 'The Compose app service must use image giai-dau-app:deploy.'
}

& $docker @composeArgs config --quiet
if ($LASTEXITCODE -ne 0) { throw 'Docker Compose configuration is invalid.' }

$databaseHealth = & $docker inspect $databaseContainer --format '{{.State.Health.Status}}' 2>$null
if ($LASTEXITCODE -ne 0 -or $databaseHealth.Trim() -ne 'healthy') {
  throw "PostgreSQL container $databaseContainer is not healthy; the running app was left unchanged."
}

$newImageId = & $docker image inspect $Image --format '{{.Id}}' 2>$null
if ($LASTEXITCODE -ne 0 -or -not $newImageId) {
  throw "New build image was not found: $Image"
}

$oldImageId = & $docker container inspect $containerName --format '{{.Image}}' 2>$null
if ($LASTEXITCODE -ne 0 -or -not $oldImageId) {
  throw "Current app container $containerName was not found; refusing a deployment without a rollback image."
}

& $docker image tag $oldImageId $rollbackTag
if ($LASTEXITCODE -ne 0) { throw 'Could not preserve the current app image for rollback.' }
& $docker image tag $newImageId $deployTag
if ($LASTEXITCODE -ne 0) { throw 'Could not tag the new app image for deployment.' }

function Wait-ForApp([int]$Attempts = 30) {
  for ($attempt = 0; $attempt -lt $Attempts; $attempt++) {
    Start-Sleep -Seconds 2
    try {
      $request = [System.Net.HttpWebRequest]::Create('http://127.0.0.1:8000/api/bootstrap-status')
      $request.Timeout = 2000
      $request.Proxy = $null
      $response = $request.GetResponse()
      $ok = [int]$response.StatusCode -eq 200
      $response.Close()
      if ($ok) { return $true }
    } catch { }
    $state = & $docker container inspect $containerName --format '{{.State.Status}}' 2>$null
    if ($LASTEXITCODE -eq 0 -and $state.Trim() -eq 'exited') { return $false }
  }
  return $false
}

$deploymentStarted = $false
try {
  $deploymentStarted = $true
  & $docker @composeArgs up -d --no-deps --no-build app
  if ($LASTEXITCODE -ne 0) { throw 'Compose could not start the new app container.' }

  if (-not (Wait-ForApp)) {
    $tail = & $docker container logs --tail 30 $containerName 2>&1
    throw "New app did not pass its HTTP health check.`n$tail"
  }

  Write-Output "Deployment succeeded. $containerName is healthy; PostgreSQL and its volume were not changed."
} catch {
  $deploymentError = $_
  if ($deploymentStarted) {
    & $docker image tag $oldImageId $deployTag
    if ($LASTEXITCODE -ne 0) { throw "Deployment failed and the previous image could not be restored: $deploymentError" }

    & $docker @composeArgs up -d --no-deps --no-build app
    if ($LASTEXITCODE -ne 0) { throw "Deployment failed and Compose could not restart the previous app image: $deploymentError" }

    if (-not (Wait-ForApp)) {
      throw "Deployment failed and the previous app image was restarted but did not pass its health check: $deploymentError"
    }
  }

  throw "Deployment failed; the previous healthy app image is running again. $deploymentError"
}
