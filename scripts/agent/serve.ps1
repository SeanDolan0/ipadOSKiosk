# serve.ps1
# Starts llama-server serving the local Qwen3.8-27B model on the OpenAI-compatible
# endpoint that opencode's 'local/qwen3.8' provider expects: http://localhost:8080/v1
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
#   --host 127.0.0.1      localhost only (safe, nothing exposed)
#   -c 32768              context; tune down to 16384 if RAM/CPU are tight
#   --mlock               keep model pinned in RAM (recommended)
#   -ngl 99               offload to GPU if you have one; on CPU-only set to 0
#   --jinja               enable ChatML/jinja template handling for Qwen3
#   -np 1                 single slot (stable for one agent)

$args = @(
    "-m", $Model,
    "--host", "127.0.0.1",
    "--port", "8080",
    "-c", "32768",
    "--mlock",
    "-ngl", "0",            # CPU-only; bump to 99 if you have a discrete GPU
    "--jinja",
    "-np", "1"
)

Write-Host "Starting llama-server on http://127.0.0.1:8080 ..." -ForegroundColor Cyan
Write-Host "Model: $Model" -ForegroundColor Gray
Write-Host "(Run in a NEW window so it stays up; close that window to stop the server.)" -ForegroundColor Yellow

# Launch in a detached window so THIS terminal stays usable for opencode
Start-Process -FilePath $LlamaServer -ArgumentList $args -WindowStyle Normal

Write-Host ""
Write-Host "Waiting for the server to come up (model load can take 30-120s on CPU)..." -ForegroundColor Yellow
Start-Sleep -Seconds 8
try {
    $m = Invoke-RestMethod -Uri "http://127.0.0.1:8080/v1/models" -TimeoutSec 5
    Write-Host "OK - server up. Model: $($m.data[0].id)" -ForegroundColor Green
} catch {
    Write-Host "Not up yet. Give it more time, then check:  Invoke-RestMethod http://127.0.0.1:8080/v1/models" -ForegroundColor Yellow
}
