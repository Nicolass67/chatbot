# Installe cloudflared comme service Windows (admin requis).
# Lit le token depuis deploy/cloudflared/tunnel.env — jamais affiché.
$ErrorActionPreference = "Stop"
$root = Split-Path (Split-Path $PSScriptRoot -Parent) -Parent
if ($PSScriptRoot -match "Chatbot\\scripts$") { $root = Split-Path $PSScriptRoot -Parent }
$envFile = Join-Path $root "deploy\cloudflared\tunnel.env"
$cf = "${env:ProgramFiles(x86)}\cloudflared\cloudflared.exe"
if (-not (Test-Path $cf)) { $cf = Join-Path $env:ProgramFiles "cloudflared\cloudflared.exe" }
if (-not (Test-Path $cf)) { throw "cloudflared introuvable" }
if (-not (Test-Path $envFile)) { throw "Fichier manquant: deploy/cloudflared/tunnel.env" }
$token = $null
foreach ($line in Get-Content $envFile) {
  if ($line -match '^\s*CLOUDFLARE_TUNNEL_TOKEN\s*=\s*(.+)\s*$') {
    $token = $matches[1].Trim().Trim('"').Trim("'")
    break
  }
}
if (-not $token -or $token -eq "<TOKEN>" -or $token.Length -lt 20) {
  throw "Token invalide ou placeholder dans tunnel.env"
}
Write-Host "Installation service cloudflared (token len=$($token.Length))..."
& $cf service install $token
Write-Host "Done."
