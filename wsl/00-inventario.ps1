# =============================================================================
#  FASE 0 - Inventario del mini PC
#  SOLO LEE. No instala, no cambia, no borra nada.
#
#  Uso (PowerShell normal, no hace falta administrador):
#     cd C:\claude\mediastack\wsl
#     powershell -ExecutionPolicy Bypass -File .\00-inventario.ps1
#
#  Deja el informe en:  C:\claude\mediastack\wsl\inventario.txt
# =============================================================================

$ErrorActionPreference = 'Continue'
$salida = Join-Path $PSScriptRoot 'inventario.txt'
$lineas = New-Object System.Collections.Generic.List[string]

function Anota($texto) {
    $lineas.Add($texto) | Out-Null
    Write-Host $texto
}

function Titulo($texto) {
    Anota ""
    Anota "== $texto =="
}

Anota "INVENTARIO MINI PC - $(Get-Date -Format 'yyyy-MM-dd HH:mm')"
Anota "Equipo: $env:COMPUTERNAME"

# ---------------------------------------------------------------- Windows ---
Titulo "Windows"
$os = Get-CimInstance Win32_OperatingSystem
Anota ("Version   : {0} (build {1})" -f $os.Caption, $os.BuildNumber)
$build = [int]$os.BuildNumber
if ($build -ge 22000)      { Anota "Resultado : Windows 11 - OK para WSL2" }
elseif ($build -ge 19041)  { Anota "Resultado : Windows 10 2004+ - OK para WSL2" }
else                       { Anota "Resultado : ATENCION - build $build es anterior a 19041. WSL2 NO es compatible" }

# -------------------------------------------------------------------- CPU ---
Titulo "CPU"
$cpu = Get-CimInstance Win32_Processor | Select-Object -First 1
Anota ("Modelo    : {0}" -f $cpu.Name.Trim())
Anota ("Nucleos   : {0} fisicos / {1} logicos" -f $cpu.NumberOfCores, $cpu.NumberOfLogicalProcessors)

$cs = Get-CimInstance Win32_ComputerSystem
if ($cs.HypervisorPresent) {
    Anota "Virtualiz.: hipervisor ACTIVO (Hyper-V/WSL2 ya en marcha o disponible) - OK"
} elseif ($cpu.VirtualizationFirmwareEnabled) {
    Anota "Virtualiz.: habilitada en BIOS, hipervisor aun no activo - OK"
} else {
    Anota "Virtualiz.: NO detectada -> hay que activarla en la BIOS/UEFI"
    Anota "            (Intel VT-x / AMD-V, suele estar en Advanced o CPU Configuration)"
}

# -------------------------------------------------------------------- RAM ---
Titulo "Memoria"
$ramGB = [math]::Round($cs.TotalPhysicalMemory / 1GB, 1)
$libreGB = [math]::Round($os.FreePhysicalMemory / 1MB, 1)
Anota ("RAM total : {0} GB" -f $ramGB)
Anota ("RAM libre : {0} GB ahora mismo" -f $libreGB)
$r = [math]::Floor($ramGB)
if     ($r -ge 16) { $sugerida = $r - 5; Anota "Resultado : OK - cabe Immich completo, con machine learning" }
elseif ($r -ge 12) { $sugerida = $r - 4; Anota "Resultado : OK - justo para machine learning, vigilar picos" }
else               { $sugerida = [math]::Max(4, $r - 3)
                     Anota "Resultado : JUSTO - Immich pide 6 GB minimo y 8 GB recomendado PARA EL,"
                     Anota "            no para el equipo entero. Con esta RAM hay que montarlo"
                     Anota "            SIN machine learning (sin caras ni busqueda por contenido)"
                     Anota "            y encenderlo a ratos. Ver PLAN.md seccion 3" }
$swap = if ($sugerida -lt 8) { 6 } else { 4 }
Anota ("Sugerido para .wslconfig : memory={0}GB  processors={1}  swap={2}GB" -f `
       $sugerida, ([math]::Max(2, $cpu.NumberOfLogicalProcessors - 1)), $swap)

# ------------------------------------------------------------------ Discos ---
Titulo "Discos"
Get-Volume | Where-Object { $_.DriveLetter } | ForEach-Object {
    $totGB = [math]::Round($_.Size / 1GB, 1)
    $libGB = [math]::Round($_.SizeRemaining / 1GB, 1)
    Anota ("{0}:  {1,7} GB libres de {2,7} GB   ({3})" -f $_.DriveLetter, $libGB, $totGB, $_.FileSystemType)
}
$c = Get-Volume -DriveLetter C -ErrorAction SilentlyContinue
if ($c) {
    $libC = [math]::Round($c.SizeRemaining / 1GB, 1)
    if ($libC -lt 60) { Anota "Resultado : ATENCION - solo $libC GB libres en C:. El runbook pide >= 60 GB" }
    else              { Anota "Resultado : OK ($libC GB libres en C:)" }
}
# Tipo de disco: SSD o HDD (Postgres quiere SSD)
try {
    Get-PhysicalDisk | ForEach-Object {
        Anota ("Disco fisico: {0} - {1} - {2} GB" -f $_.FriendlyName, $_.MediaType, [math]::Round($_.Size/1GB,0))
    }
} catch { Anota "Disco fisico: no se ha podido leer (no critico)" }

# ------------------------------------------------------------------- GPU ---
Titulo "Grafica (para la fase 8, opcional)"
Get-CimInstance Win32_VideoController | ForEach-Object {
    Anota ("{0}  |  driver {1}" -f $_.Name, $_.DriverVersion)
}

# ------------------------------------------------------------------- WSL ---
Titulo "Estado de WSL"
$wslExe = "$env:SystemRoot\System32\wsl.exe"
if (Test-Path $wslExe) {
    $estado = & $wslExe --status 2>&1 | Out-String
    if ($LASTEXITCODE -eq 0 -and $estado.Trim()) {
        Anota "WSL ya instalado:"
        Anota ($estado.Trim())
        Anota "--- distribuciones ---"
        Anota ((& $wslExe --list --verbose 2>&1 | Out-String).Trim())
    } else {
        Anota "wsl.exe existe pero no responde: WSL aun no esta instalado del todo"
    }
} else {
    Anota "WSL NO instalado (no existe wsl.exe)"
}

# ------------------------------------------------------------------- Red ---
Titulo "Red y NAS"
Get-NetIPAddress -AddressFamily IPv4 | Where-Object { $_.IPAddress -notlike '127.*' -and $_.IPAddress -notlike '169.254.*' } |
    ForEach-Object { Anota ("IP local  : {0}  ({1})" -f $_.IPAddress, $_.InterfaceAlias) }

$nas = Test-Connection -ComputerName 192.168.1.205 -Count 2 -Quiet -ErrorAction SilentlyContinue
if ($nas) { Anota "NAS 192.168.1.205 : responde al ping - OK" }
else      { Anota "NAS 192.168.1.205 : NO responde. Comprobar que el mini PC esta en la misma red" }

# ---------------------------------------------------------------- Resumen ---
Titulo "Resumen"
Anota "Guarda este fichero y pasamelo para revisar la fase 0 antes de instalar nada."
Anota ""

$lineas | Set-Content -Path $salida -Encoding UTF8
Write-Host ""
Write-Host "Informe guardado en: $salida" -ForegroundColor Green
