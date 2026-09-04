<#
  Active Wake-on-LAN sur Intel X520 (Ethernet 2, MAC 9C:69:B4:60:70:6B).

  IMPORTANT — lancer UNE SEULE FOIS, manuellement :
  1. Clic droit sur PowerShell → « Exécuter en tant qu'administrateur »
  2. Puis :  Set-ExecutionPolicy -Scope Process Bypass -Force
              d:\Chatbot\scripts\enable-wol-x520.ps1

  Ne pas lancer via Cursor / double-clic : ça provoque des popups UAC en boucle.
#>

$isAdmin = ([Security.Principal.WindowsPrincipal][Security.Principal.WindowsIdentity]::GetCurrent()).IsInRole(
  [Security.Principal.WindowsBuiltInRole]::Administrator
)
if (-not $isAdmin) {
  Write-Host ''
  Write-Host 'ERREUR : droits administrateur requis.' -ForegroundColor Red
  Write-Host 'Ouvre PowerShell en admin (clic droit), puis relance ce script UNE fois.'
  Write-Host 'Ce script ne demande jamais les droits tout seul — pas de popup en boucle.'
  Write-Host ''
  exit 1
}

$ErrorActionPreference = 'Continue'

$adapterName = 'Ethernet 2'
$macExpected = '9C-69-B4-60-70-6B'

$nic = Get-NetAdapter -Name $adapterName -ErrorAction SilentlyContinue
if (-not $nic) {
  Write-Host "Adaptateur '$adapterName' introuvable." -ForegroundColor Red
  exit 1
}
if ($nic.MacAddress -ne $macExpected) {
  Write-Warning "MAC inattendue: $($nic.MacAddress) (attendu $macExpected)"
}

Write-Host "Adaptateur: $($nic.InterfaceDescription) ($($nic.MacAddress))"

foreach ($prop in @(
    @{ Keyword = '*WakeOnMagicPacket'; Value = 'Activé(e)' },
    @{ Keyword = '*WakeOnMagicPacket'; Value = 'Enabled' }
  )) {
  try {
    Set-NetAdapterAdvancedProperty -Name $adapterName -RegistryKeyword $prop.Keyword -RegistryValue $prop.Value -ErrorAction Stop
    Write-Host "OK $($prop.Keyword) = $($prop.Value)"
    break
  } catch {
    Write-Host "Info: $($prop.Keyword) non modifiable via pilote — $($_.Exception.Message)"
  }
}

$classBase = 'HKLM:\SYSTEM\CurrentControlSet\Control\Class\{4d36e972-e325-11ce-bfc1-08002be10318}'
$regKey = Get-ChildItem $classBase -ErrorAction SilentlyContinue | ForEach-Object {
  $p = Get-ItemProperty $_.PSPath -ErrorAction SilentlyContinue
  if ($p.DriverDesc -like '*X520*') { $_.PSPath }
} | Select-Object -First 1

if ($regKey) {
  New-ItemProperty -Path $regKey -Name '*WakeOnMagicPacket' -Value '1' -PropertyType String -Force | Out-Null
  New-ItemProperty -Path $regKey -Name '*WakeOnPattern' -Value '1' -PropertyType String -Force | Out-Null
  New-ItemProperty -Path $regKey -Name 'PnPCapabilities' -Value 0 -PropertyType DWord -Force | Out-Null
  Write-Host "OK registre: $regKey"
} else {
  Write-Warning 'Clé registre Intel X520 introuvable'
}

try {
  Set-NetAdapterPowerManagement -Name $adapterName -WakeOnMagicPacket Enabled -ErrorAction Stop
  Set-NetAdapterPowerManagement -Name $adapterName -AllowComputerToWakeDevice Enabled -ErrorAction Stop
  Write-Host 'OK gestion alimentation adaptateur'
} catch {
  Write-Warning "Gestion alimentation: $($_.Exception.Message)"
}

$pnp = Get-PnpDevice -Class Net -ErrorAction SilentlyContinue | Where-Object { $_.FriendlyName -like '*X520*' } | Select-Object -First 1
if ($pnp) {
  powercfg -deviceenablewake $pnp.FriendlyName 2>$null
  Write-Host "powercfg -deviceenablewake exécuté pour $($pnp.FriendlyName)"
}

Restart-NetAdapter -Name $adapterName -Confirm:$false -ErrorAction SilentlyContinue
Start-Sleep -Seconds 2

Write-Host ''
Write-Host '=== Vérification (Intel X520 doit apparaître ci-dessous) ==='
powercfg /devicequery wake_armed
Write-Host ''
Write-Host 'Si X520 absent : active Wake-on-LAN / PME dans le BIOS, puis redémarre le PC.'
