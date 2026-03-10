#!/usr/bin/env pwsh
# =============================================================================
# Clarity Rewrite - Windows Local Development Setup
# =============================================================================
# Run from project root: .\scripts\setup-windows.ps1
# Prereqs: Docker Desktop, Python 3.12+, Node.js 20+
# =============================================================================

$ErrorActionPreference = "Stop"
$ROOT = Split-Path -Parent $PSScriptRoot

Write-Host ""
Write-Host "=============================================" -ForegroundColor Cyan
Write-Host "  Clarity Rewrite - Windows Setup" -ForegroundColor Cyan
Write-Host "=============================================" -ForegroundColor Cyan
Write-Host ""

# --- 1. Check prerequisites ---
Write-Host "[1/8] Checking prerequisites..." -ForegroundColor Yellow
$missing = @()
if (-not (Get-Command docker -ErrorAction SilentlyContinue)) { $missing += "Docker" }
if (-not (Get-Command python -ErrorAction SilentlyContinue)) { $missing += "Python" }
if (-not (Get-Command node -ErrorAction SilentlyContinue)) { $missing += "Node.js" }
if (-not (Get-Command npm -ErrorAction SilentlyContinue)) { $missing += "npm" }

if ($missing.Count -gt 0) {
    Write-Host "  MISSING: $($missing -join ', ')" -ForegroundColor Red
    Write-Host "  Install the missing tools and re-run." -ForegroundColor Red
    exit 1
}

Write-Host "  Python:  $(python --version 2>&1)" -ForegroundColor Green
Write-Host "  Node:    $(node --version 2>&1)" -ForegroundColor Green
Write-Host "  Docker:  $(docker --version 2>&1)" -ForegroundColor Green

try { docker info 2>&1 | Out-Null; Write-Host "  Docker:  Running" -ForegroundColor Green }
catch { Write-Host "  Docker Desktop is not running. Start it and re-run." -ForegroundColor Red; exit 1 }

# --- 2. Create .env ---
Write-Host "`n[2/8] Setting up environment..." -ForegroundColor Yellow
$envFile = Join-Path $ROOT ".env"
if (-not (Test-Path $envFile)) {
    $envExample = Join-Path $ROOT ".env.example"
    if (Test-Path $envExample) { Copy-Item $envExample $envFile }
    else {
        @"
CLARITY_SQL_DB=clarity
CLARITY_SQL_USER=clarity
CLARITY_SQL_PASSWORD=clarity
CLARITY_SQL_HOST=localhost
CLARITY_SQL_PORT=5432
CLARITY_KC_REALM=clarity
CLARITY_KC_ADMIN=admin
CLARITY_KC_ADMIN_PASSWORD=admin
CLARITY_KC_MGMT_CLIENT_SECRET=
COMP_OIDC_CLIENT_ID=clarity-app
COMP_OIDC_CLIENT_SECRET=
META_OPENAI_URL=
META_OPENAI_KEY=
ARCHER_USERNAME=
ARCHER_PASSWORD=
ARCHER_INSTANCE_NAME=ArcherRTX PROD
ARCHER_BASE_URI=https://archergrc.corp.ray.com
ARCHER_SOAP_SEARCH_URI=
ARCHER_SOAP_GENERAL_URI=
MAPPING_REPORT=
SEED_DATA=true
SEED_RAG=false
NUXT_API_BASE=http://localhost:4000
NUXT_PUBLIC_OAUTH_KEYCLOAK_REDIRECT_URL=http://localhost:3001/auth/callback
NUXT_SESSION_PASSWORD=clarity-session-password-minimum-32-characters-long
"@ | Out-File -FilePath $envFile -Encoding utf8NoBOM
    }
    Write-Host "  Created .env" -ForegroundColor Green
} else { Write-Host "  .env exists, skipping" -ForegroundColor Green }

# Load env vars into session
Get-Content $envFile | ForEach-Object {
    if ($_ -match '^([^#][^=]+)=(.*)$') {
        [System.Environment]::SetEnvironmentVariable($Matches[1].Trim(), $Matches[2].Trim(), "Process")
    }
}

# --- 3. Start Docker (PostgreSQL + Keycloak) ---
Write-Host "`n[3/8] Starting PostgreSQL + Keycloak..." -ForegroundColor Yellow
Push-Location $ROOT
docker compose up -d db keycloak
Pop-Location

Write-Host "  Waiting for PostgreSQL..." -ForegroundColor Gray
for ($i = 0; $i -lt 30; $i++) {
    $r = docker exec clarity-db pg_isready -U clarity 2>&1
    if ($r -match "accepting") { Write-Host "  PostgreSQL ready" -ForegroundColor Green; break }
    Start-Sleep 2
}

Write-Host "  Waiting for Keycloak (~30s)..." -ForegroundColor Gray
Start-Sleep 15
for ($i = 0; $i -lt 20; $i++) {
    try {
        $resp = Invoke-WebRequest -Uri "http://localhost:8080/kc/health/ready" -UseBasicParsing -TimeoutSec 3 -ErrorAction SilentlyContinue
        if ($resp.StatusCode -eq 200) { Write-Host "  Keycloak ready" -ForegroundColor Green; break }
    } catch {}
    Start-Sleep 3
}

# --- 4. Python venv + deps ---
Write-Host "`n[4/8] Setting up Python backend..." -ForegroundColor Yellow
$backendDir = Join-Path $ROOT "backend"
$venvDir = Join-Path $backendDir ".venv"

if (-not (Test-Path $venvDir)) {
    python -m venv $venvDir
    Write-Host "  Created venv" -ForegroundColor Green
}

& (Join-Path $venvDir "Scripts" "Activate.ps1")
Push-Location $backendDir
pip install -r requirements.txt --quiet 2>&1 | Out-Null
Pop-Location
Write-Host "  Dependencies installed" -ForegroundColor Green

# --- 5. Node.js frontend ---
Write-Host "`n[5/8] Setting up Nuxt frontend..." -ForegroundColor Yellow
$frontendDir = Join-Path $ROOT "frontend"
if (-not (Test-Path (Join-Path $frontendDir "node_modules"))) {
    Push-Location $frontendDir
    npm install --silent 2>&1 | Out-Null
    Pop-Location
    Write-Host "  npm install complete" -ForegroundColor Green
} else { Write-Host "  node_modules exists, skipping" -ForegroundColor Green }

# --- 6. Seed data ---
Write-Host "`n[6/8] Checking seed data..." -ForegroundColor Yellow
$seedSrc = Join-Path $backendDir "seed" "data.json"
$seedDst = Join-Path $backendDir "src" "clarity" "seed"
if (-not (Test-Path $seedDst)) { New-Item -ItemType Directory -Path $seedDst -Force | Out-Null }
if ((Test-Path $seedSrc) -and (-not (Test-Path (Join-Path $seedDst "data.json")))) {
    Copy-Item $seedSrc (Join-Path $seedDst "data.json")
}
if (Test-Path $seedSrc) { Write-Host "  Seed data ready" -ForegroundColor Green }
else { Write-Host "  WARNING: seed/data.json missing!" -ForegroundColor Red }

# --- 7. Fix CRLF → LF ---
Write-Host "`n[7/8] Fixing line endings..." -ForegroundColor Yellow
Get-ChildItem -Path $backendDir -Recurse -Filter "*.py" | ForEach-Object {
    $c = [IO.File]::ReadAllText($_.FullName)
    if ($c -match "`r`n") { [IO.File]::WriteAllText($_.FullName, $c -replace "`r`n","`n") }
}
Write-Host "  LF line endings applied" -ForegroundColor Green

# --- 8. Create start scripts ---
Write-Host "`n[8/8] Creating helper scripts..." -ForegroundColor Yellow

@"
@echo off
cd /d "$backendDir"
call .venv\Scripts\activate.bat
set SEED_DATA=true
set CLARITY_SQL_HOST=localhost
set CLARITY_SQL_PORT=5432
set CLARITY_SQL_DB=clarity
set CLARITY_SQL_USER=clarity
set CLARITY_SQL_PASSWORD=clarity
set CLARITY_KC_REALM=clarity
set CLARITY_KC_MGMT_CLIENT_SECRET=
set COMP_OIDC_CLIENT_ID=clarity-app
set COMP_OIDC_CLIENT_SECRET=
set META_OPENAI_URL=
set META_OPENAI_KEY=
set ARCHER_USERNAME=
set ARCHER_PASSWORD=
set ARCHER_INSTANCE_NAME=ArcherRTX PROD
set ARCHER_BASE_URI=https://archergrc.corp.ray.com
set ARCHER_SOAP_SEARCH_URI=
set ARCHER_SOAP_GENERAL_URI=
set MAPPING_REPORT=
uvicorn src.clarity.api:api --host 0.0.0.0 --port 4000 --reload
"@ | Out-File -FilePath (Join-Path $ROOT "start-backend.bat") -Encoding ascii

@"
@echo off
cd /d "$frontendDir"
npm run dev
"@ | Out-File -FilePath (Join-Path $ROOT "start-frontend.bat") -Encoding ascii

Write-Host "  Created start-backend.bat" -ForegroundColor Green
Write-Host "  Created start-frontend.bat" -ForegroundColor Green

# --- Done ---
Write-Host ""
Write-Host "=============================================" -ForegroundColor Cyan
Write-Host "  Setup Complete!" -ForegroundColor Cyan
Write-Host "=============================================" -ForegroundColor Cyan
Write-Host ""
Write-Host "  PostgreSQL:  localhost:5432" -ForegroundColor Gray
Write-Host "  Keycloak:    http://localhost:8080/kc/  (admin/admin)" -ForegroundColor Gray
Write-Host ""
Write-Host "  To start backend:  .\start-backend.bat" -ForegroundColor Yellow
Write-Host "  To start frontend: .\start-frontend.bat  (new terminal)" -ForegroundColor Yellow
Write-Host ""
Write-Host "  Frontend:    http://localhost:3001" -ForegroundColor Green
Write-Host "  Backend API: http://localhost:4000/docs" -ForegroundColor Green
Write-Host "  Keycloak:    http://localhost:8080/kc/admin" -ForegroundColor Green
Write-Host ""
Write-Host "  First run:  SEED_DATA=true  (loads questionnaire)" -ForegroundColor Yellow
Write-Host "  After that: SEED_DATA=false (avoid duplicates)" -ForegroundColor Yellow
Write-Host ""
