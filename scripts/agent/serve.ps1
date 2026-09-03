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

# Detect LAN IP(s) for user convenience
$LanIps = Get-NetIPAddress -AddressFamily IPv4 -ErrorAction SilentlyContinue |
    Where-Object { $_.InterfaceAlias -notlike "*Loopback*" -and $_.IPAddress -notlike "169.254*" -and $_.IPAddress -notlike "172.*" } |
    Select-Object -ExpandProperty IPAddress
$PrimaryIp = if ($LanIps) { $LanIps[0] } else { "<THIS_PC_LAN_IP>" }

# Common llama-server flags:
#   -m <model>            GGUF to load
#   --port 8080           OpenAI-compatible port (matches opencode provider)
#   --host 0.0.0.0        bind all interfaces so the Mac can reach it over the LAN
#                          (no auth -- only run on a trusted network)
#   -dev Vulkan1          Offload explicitly to NVIDIA GeForce RTX 5070 Ti (Vulkan1)
#   -ngl 99               offload ALL layers to the NVIDIA GPU
#   -c 32768              32k context (fits safely in 12GB VRAM with model + KV cache)
#   -ctk q8_0             quantized KV cache K (saves ~50% VRAM)
#   -ctv q8_0             quantized KV cache V (saves ~50% VRAM)
#   --mlock               keep model pinned in RAM (recommended)
#   --jinja               enable ChatML/jinja template handling for Qwen3
#   -np 1                 single slot (stable for one agent)
#
# Health check on the Mac:  curl http://<WINDOWS_IP>:8080/v1/models

$args = @(
    "-m", $Model,
    "--host", "0.0.0.0",
    "--port", "8080",
    "-dev", "Vulkan1",       # NVIDIA GeForce RTX 5070 Ti Laptop GPU
    "-ngl", "99",            # Offload all layers to GPU
    "-c", "32768",           # 32k context fits in 12 GB VRAM
    "-ctk", "q8_0",          # 8-bit quantized KV cache K
    "-ctv", "q8_0",          # 8-bit quantized KV cache V
    "--mlock",
    "--jinja",
    "-np", "1"
)

Write-Host "Starting llama-server on http://0.0.0.0:8080 (LAN-reachable) ..." -ForegroundColor Cyan
Write-Host "Target Device: Vulkan1 (NVIDIA GeForce RTX 5070 Ti)" -ForegroundColor Cyan
Write-Host "Model: $Model" -ForegroundColor Gray
Write-Host "Detected LAN IP(s): $($LanIps -join ', ')" -ForegroundColor Cyan
Write-Host "(Run in a detached window so it stays up; close that window to stop the server.)" -ForegroundColor Yellow

# Launch in a detached window so THIS terminal stays usable for opencode
Start-Process -FilePath $LlamaServer -ArgumentList $args -WindowStyle Normal

Write-Host ""
Write-Host "Waiting for server readiness..." -ForegroundColor Yellow
$maxWaitSec = 60
$sw = [System.Diagnostics.Stopwatch]::StartNew()
$isReady = $false

while ($sw.Elapsed.TotalSeconds -lt $maxWaitSec) {
    Start-Sleep -Seconds 3
    try {
        $m = Invoke-RestMethod -Uri "http://127.0.0.1:8080/v1/models" -TimeoutSec 2
        $isReady = $true
        break
    } catch {
        Write-Host "  loading model... ($([int]$sw.Elapsed.TotalSeconds)s)" -ForegroundColor DarkGray
    }
}

if ($isReady) {
    Write-Host "`n=== llama-server is READY ===" -ForegroundColor Green
    Write-Host "Model: $($m.data[0].id)" -ForegroundColor Green
    Write-Host "Local endpoint:  http://127.0.0.1:8080/v1" -ForegroundColor Green
    Write-Host "`nFrom your Mac terminal, run:" -ForegroundColor Cyan
    Write-Host "  export WINDOWS_IP=$PrimaryIp" -ForegroundColor White
    Write-Host "  curl http://${PrimaryIp}:8080/v1/models" -ForegroundColor White
    Write-Host "`nNote: If the Mac cannot connect, make sure Windows Firewall allows TCP 8080:" -ForegroundColor Yellow
    Write-Host "  netsh advfirewall firewall add rule name=`"llama-server 8080`" dir=in action=allow protocol=TCP localport=8080" -ForegroundColor DarkGray
} else {
    Write-Host "`nServer did not respond within ${maxWaitSec}s." -ForegroundColor Yellow
    Write-Host "Check the llama-server console window for error messages." -ForegroundColor Yellow
    Write-Host "You can test manually with:  Invoke-RestMethod http://127.0.0.1:8080/v1/models" -ForegroundColor Gray
}
