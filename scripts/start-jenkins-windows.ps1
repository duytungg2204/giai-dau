$ErrorActionPreference = 'Stop'

$runtimeDir = Join-Path $env:LOCALAPPDATA 'Programs\JenkinsRuntime'
$jdkRoot = Join-Path $runtimeDir 'jdk-21'
$jenkinsDir = Join-Path $runtimeDir 'jenkins'
$dockerDesktopToolsDir = Join-Path $env:LOCALAPPDATA 'Programs\DockerDesktop\resources\bin'
$jenkinsHome = Join-Path $env:USERPROFILE '.jenkins-home'
$warPath = Join-Path $jenkinsDir 'jenkins.war'
$jdk = Get-ChildItem -LiteralPath $jdkRoot -Directory -Filter 'jdk-*' | Select-Object -First 1
if (-not $jdk) { throw "Java 21 is missing under $jdkRoot" }

$javaPath = Join-Path $jdk.FullName 'bin\java.exe'
if (-not (Test-Path -LiteralPath $javaPath -PathType Leaf)) { throw "Java executable is missing: $javaPath" }
if (-not (Test-Path -LiteralPath $warPath -PathType Leaf)) { throw "Jenkins WAR is missing: $warPath" }

$existing = Get-CimInstance Win32_Process | Where-Object {
  $_.Name -eq 'java.exe' -and $_.CommandLine -like '*jenkins.war*' -and $_.CommandLine -like '*httpPort=8081*'
} | Select-Object -First 1
if ($existing) {
  try {
    $response = Invoke-WebRequest -Uri 'http://127.0.0.1:8081/login' -UseBasicParsing -TimeoutSec 5
    if ([int]$response.StatusCode -eq 200) {
      Write-Output 'Jenkins is already running at http://localhost:8081'
      exit 0
    }
  } catch { }
  throw "Jenkins process $($existing.ProcessId) is running but its web endpoint is not ready."
}

New-Item -ItemType Directory -Force -Path $jenkinsHome | Out-Null
$env:JENKINS_HOME = $jenkinsHome
$env:JAVA_HOME = $jdk.FullName
$env:PATH = "C:\Program Files\nodejs;C:\Program Files\Git\cmd;$dockerDesktopToolsDir;$($jdk.FullName)\bin;$env:PATH"
$stdout = Join-Path $jenkinsDir 'jenkins.out.log'
$stderr = Join-Path $jenkinsDir 'jenkins.err.log'
$arguments = "-Xms256m -Xmx1024m -Djava.awt.headless=true -jar `"$warPath`" --httpPort=8081"
$process = Start-Process -FilePath $javaPath -ArgumentList $arguments -WorkingDirectory $jenkinsDir `
  -WindowStyle Hidden -RedirectStandardOutput $stdout -RedirectStandardError $stderr -PassThru

$ready = $false
for ($attempt = 0; $attempt -lt 36; $attempt++) {
  Start-Sleep -Seconds 5
  try {
    $response = Invoke-WebRequest -Uri 'http://127.0.0.1:8081/login' -UseBasicParsing -TimeoutSec 5
    if ([int]$response.StatusCode -eq 200) { $ready = $true; break }
  } catch {
    if ($process.HasExited) { break }
  }
}

if (-not $ready) {
  Get-Content -LiteralPath $stderr -Tail 40 -ErrorAction SilentlyContinue
  throw 'Jenkins did not become ready on port 8081.'
}

Write-Output "Jenkins is running at http://localhost:8081 (PID $($process.Id))."
$adminCredentials = Join-Path $jenkinsHome 'secrets\jenkins-admin-credentials.txt'
$initialPassword = Join-Path $jenkinsHome 'secrets\initialAdminPassword'
if (Test-Path -LiteralPath $adminCredentials -PathType Leaf) {
  Write-Output "Admin login details are stored locally in $adminCredentials"
} elseif (Test-Path -LiteralPath $initialPassword -PathType Leaf) {
  Write-Output "Complete the setup wizard with the password in $initialPassword"
}
