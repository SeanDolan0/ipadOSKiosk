# download-model.ps1
# Downloads the Unsloth Qwen3.8-27B-UD-Q2_K_XL.gguf (9.83 GB) from Hugging Face.
# Run from the repo root or anywhere; saves into .\models\
#
#   powershell -ExecutionPolicy Bypass -File .\scripts\agent\download-model.ps1
#
# Required: curl.exe (ships with Windows 10/11). No auth needed (public repo).

$ErrorActionPreference = "Stop"
$Repo  = "unsloth/Qwen3.8-27B-GGUF"
$File  = "Qwen3.8-27B-UD-Q2_K_XL.gguf"
$HfUrl = "https://huggingface.co/$Repo/resolve/main/$File"

$ModelDir = Join-Path $PSScriptRoot "..\..\models"
New-Item -ItemType Directory -Force -Path $ModelDir | Out-Null
$OutPath = Join-Path $ModelDir $File

if (Test-Path $OutPath) {
    $size = (Get-Item $OutPath).Length / 1GB
    Write-Host "Model already present: $OutPath ($([math]::Round($size,2)) GB)" -ForegroundColor Green
    exit 0
}

Write-Host "Downloading $File from $HfUrl ..." -ForegroundColor Cyan
Write-Host "Destination: $OutPath" -ForegroundColor Cyan
Write-Host "Size ~9.83 GB. This will take a while on slow links." -ForegroundColor Yellow

# -L follow redirects (HF redirects to CDN), -C - resume on partial download
# --ssl-no-revoke prevents CRYPT_E_NO_REVOCATION_CHECK (0x80092012) on Windows Schannel
& curl.exe --ssl-no-revoke -L -C - -o $OutPath $HfUrl
if ($LASTEXITCODE -ne 0) {
    Write-Error "curl failed with exit code $LASTEXITCODE"
}

$finalSize = (Get-Item $OutPath).Length / 1GB
Write-Host "Done: $([math]::Round($finalSize,2)) GB at $OutPath" -ForegroundColor Green
