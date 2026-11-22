$ErrorActionPreference = "Stop"

# Starts a Cloudflare quick tunnel from the public HTTPS edge to the local
# WebSocket host on port 9080. Web clients then join with the printed wss:// URL.

$downloadDir = Join-Path $PSScriptRoot "downloads"
$cloudflared = Join-Path $downloadDir "cloudflared.exe"

if (-not (Test-Path $cloudflared)) {
    Write-Host "cloudflared.exe not found. Downloading official Windows build..."
    New-Item -ItemType Directory -Force -Path $downloadDir | Out-Null
    $url = "https://github.com/cloudflare/cloudflared/releases/latest/download/cloudflared-windows-amd64.exe"
    Invoke-WebRequest -Uri $url -OutFile $cloudflared
    Write-Host "Saved to $cloudflared"
}

Write-Host ""
Write-Host "Starting tunnel: https://<random>.trycloudflare.com  ->  ws://127.0.0.1:9080"
Write-Host "Copy the https:// URL below and give it to Web players as:"
Write-Host "  https://<your-pages-site>/?server=wss://<random>.trycloudflare.com"
Write-Host "Press Ctrl+C to stop the tunnel."
Write-Host ""

& $cloudflared tunnel --url http://127.0.0.1:9080
