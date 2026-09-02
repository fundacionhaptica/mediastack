# FASE 8b - abre en el firewall de Windows los puertos del stack, para que se vean
# desde la LAN una vez que .wslconfig esta en networkingMode=mirrored.
#
# Con la red en modo espejo, el trafico hacia WSL deja de ser "trafico local de una
# VM NAT" y pasa por el firewall de Windows como cualquier otro. Sin estas reglas,
# WSL comparte la IP de Windows pero el firewall sigue tirando las conexiones y el
# sintoma es identico a no haber cambiado nada.
#
# Ejecutar en PowerShell COMO ADMINISTRADOR:
#   powershell -ExecutionPolicy Bypass -File \\wsl.localhost\Ubuntu-24.04\home\jaime\mediastack\wsl\08b-red-mirrored.ps1
#
# Es idempotente: si una regla ya existe, la deja como esta.

$ErrorActionPreference = 'Stop'

$id = ([Security.Principal.WindowsIdentity]::GetCurrent())
$esAdmin = (New-Object Security.Principal.WindowsPrincipal($id)).IsInRole(
    [Security.Principal.WindowsBuiltInRole]::Administrator)
if (-not $esAdmin) {
    Write-Error "Esto necesita PowerShell como administrador."
}

# Perfil de firewall de WSL. El GUID es fijo y lo define Windows: es el contenedor
# de red de WSL, no algo de este equipo.
$wslPerfil = '{40E0AC32-46A5-438A-A0B2-2B479E8F2E90}'

if (-not (Get-Command New-NetFirewallHyperVRule -ErrorAction SilentlyContinue)) {
    Write-Error @"
Este Windows no tiene los cmdlets de firewall de Hyper-V (New-NetFirewallHyperVRule).
Hacen falta Windows 11 22H2+ y WSL 2.0+. Comprueba con 'winver' y 'wsl --version'.
"@
}

# Solo los tres servicios del stack. A proposito NO se abre nada mas:
#  - Homepage (3000) publica en 127.0.0.1 y se sirve por Caddy; no va a la LAN.
#  - Caddy escucha en la IP del tailnet, que no pasa por aqui.
$puertos = @(
    @{ Nombre = 'WSL-Immich';    Puerto = 2283 },
    @{ Nombre = 'WSL-Navidrome'; Puerto = 4533 },
    @{ Nombre = 'WSL-Jellyfin';  Puerto = 8096 }
)

foreach ($p in $puertos) {
    $existente = Get-NetFirewallHyperVRule -Name $p.Nombre -ErrorAction SilentlyContinue
    if ($existente) {
        Write-Host ("  ya existe: {0} (puerto {1})" -f $p.Nombre, $p.Puerto)
        continue
    }
    New-NetFirewallHyperVRule `
        -Name        $p.Nombre `
        -DisplayName ("{0} (mediastack)" -f $p.Nombre) `
        -Direction   Inbound `
        -VMCreatorId $wslPerfil `
        -Protocol    TCP `
        -LocalPorts  $p.Puerto `
        -Action      Allow | Out-Null
    Write-Host ("  creada:    {0} (puerto {1})" -f $p.Nombre, $p.Puerto)
}

Write-Host ""
Write-Host "Reglas puestas. Recuerda que .wslconfig tiene que estar en modo espejo y"
Write-Host "que hace falta 'wsl --shutdown' para que el cambio de red se aplique."
Write-Host ""
Write-Host "Comprobacion, desde OTRO equipo de la red:"
Write-Host "  curl -I http://192.168.1.227:2283"
