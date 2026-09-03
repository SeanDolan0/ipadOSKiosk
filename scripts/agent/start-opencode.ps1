# start-opencode.ps1
# Starts the opencode harness in this directory, wired to the local model.
# opencode reads the GLOBAL config (~/.config/opencode/opencode.json) which
# already defines provider 'local' -> http://localhost:8080/v1, model local/qwen3.8.
# THIS script just verifies the server is reachable and launches opencode here.
#
#   powershell -ExecutionPolicy Bypass -File .\scripts\agent\start-opencode.ps1

$ErrorActionPreference = "Stop"

# 1. Ensure llama-server is up
try {
    $m = Invoke-RestMethod -Uri "http://127.0.0.1:8080/v1/models" -TimeoutSec 5
    Write-Host "Model server OK. Serving: $($m.data[0].id)" -ForegroundColor Green
} catch {
    Write-Error "Model server is NOT running. Start it first:  .\scripts\agent\serve.ps1"
}

# 2. Launch opencode for this folder (uses global config w/ local/qwen3.8)
$Repo = Split-Path -Parent (Split-Path -Parent $PSScriptRoot)   # repo root
Push-Location $Repo
try {
    opencode
} finally {
    Pop-Location
}
