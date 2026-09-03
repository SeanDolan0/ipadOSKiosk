# serve.ps1
# Starts llama-server serving the local Qwen3.8-27B model on the OpenAI-compatible
# endpoint that the Mac-side agent expects: http://<THIS_PC_LAN_IP>:8080/v1
#
# Serves the model on the LAN (0.0.0.0) so the Mac can reach it. No API key --
# LAN-only exposure, so keep this on a trusted network.
#
#   powershell -ExecutionPolicy Bypass -File .\scripts\agent\serve.ps1
#
# Detaches llama-server into its own window so you can keep using this terminal.
# Healthy check after start:  Invoke-RestMethod http://localhost:8080/v1/models

$ErrorActionPreference = "Stop"

# Model path (adjust if you put the GGUF elsewhere)
$ModelDir = Join-Path $PSScriptRoot "..\..\models"
$Model    = Join-Path $ModelDir "Qwen3.8-27B-UD-Q2_K_XL.gguf"

if (-not (Test-Path $Model)) {
    Write-Error "Model not found at $Model`nRun download-model.ps1 first:  .\scripts\agent\download-model.ps1"
}

# llama-server should be on PATH (installed via WinGet: ggml.llamacpp).
# If not, set $LlamaServer to the full path.
$LlamaServer = (Get-Command llama-server -ErrorAction SilentlyContinue).Source
if (-not $LlamaServer) {
    Write-Error "llama-server not found on PATH. Install via: winget install ggml.llamacpp"
}

# Common llama-server flags:
#   -m <model>            GGUF to load
#   --port 8080           OpenAI-compatible port (matches opencode provider)
#   --host 0.0.0.0        bind all interfaces so the Mac can reach it over the LAN
#                          (no auth -- only run on a trusted network)
#   -c 65536              ~64k context (fits on GPU with Q2_K_XL)
#   --mlock               keep model pinned in RAM (recommended)
#   -ngl 99               offload ALL layers to the NVIDIA GPU
#   --jinja               enable ChatML/jinja template handling for Qwen3
#   -np 1                 single slot (stable for one agent)
#
# Health check on the Mac:  curl http://<WINDOWS_IP>:8080/v1/models

$args = @(
    "-m", $Model,
    "--host", "0.0.0.0",
    "--port", "8080",
    "-c", "65536",
    "--mlock",
    "-ngl", "99",           # NVIDIA GPU: offload all layers
    "--jinja",
    "-np", "1"
)

Write-Host "Starting llama-server on http://0.0.0.0:8080 (LAN-reachable) ..." -ForegroundColor Cyan
Write-Host "Model: $Model" -ForegroundColor Gray
Write-Host "(Run in a NEW window so it stays up; close that window to stop the server.)" -ForegroundColor Yellow

# Launch in a detached window so THIS terminal stays usable for opencode
Start-Process -FilePath $LlamaServer -ArgumentList $args -WindowStyle Normal

Write-Host ""
Write-Host "Waiting for the server to come up (model load can take 30-120s on CPU)..." -ForegroundColor Yellow
Start-Sleep -Seconds 8
try {
    $m = Invoke-RestMethod -Uri "http://127.0.0.1:8080/v1/models" -TimeoutSec 5
    Write-Host "From the Mac, point your agent at:  http://<THIS_PC_LAN_IP>:8080/v1" -ForegroundColor Green
    Write-Host "OK - server up. Model: $($m.data[0].id)" -ForegroundColor Green
} catch {
    Write-Host "Not up yet. Find this PC's LAN IP (ipconfig) and give it more time, then check:  Invoke-RestMethod http://127.0.0.1:8080/v1/models" -ForegroundColor Yellow
}
