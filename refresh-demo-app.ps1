[CmdletBinding()]
param(
    [string]$Image = "ghcr.io/anilmaz/first-github-action-demo:latest",
    [string]$ContainerName = "demo-app",
    [int]$HostPort = 8080,
    [int]$ContainerPort = 80
)

$ErrorActionPreference = "Stop"

Write-Host "Pulling image: $Image ..." -ForegroundColor Cyan
docker pull $Image
if ($LASTEXITCODE -ne 0) {
    throw "docker pull failed with exit code $LASTEXITCODE."
}

$existing = docker ps -a -q -f "name=^/${ContainerName}$"
if ($existing) {
    Write-Host "Stopping existing container '$ContainerName'..." -ForegroundColor Yellow
    docker stop $ContainerName | Out-Null

    Write-Host "Removing existing container '$ContainerName'..." -ForegroundColor Yellow
    docker rm $ContainerName | Out-Null
}

Write-Host "Starting container '$ContainerName' on port $HostPort -> $ContainerPort ..." -ForegroundColor Green
docker run -d --name $ContainerName -p "${HostPort}:${ContainerPort}" $Image
if ($LASTEXITCODE -ne 0) {
    throw "docker run failed with exit code $LASTEXITCODE."
}

Write-Host "Ready! Open http://localhost:$HostPort" -ForegroundColor Green