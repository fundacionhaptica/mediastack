# =============================================================================
#  FASE 1 - Instalacion de WSL2 + Ubuntu 24.04
#
#  Uso (PowerShell COMO ADMINISTRADOR):
#     cd C:\claude\mediastack\wsl
#     powershell -ExecutionPolicy Bypass -File .\01-instalar-wsl2.ps1
#
#  Que hace:
#     1. Comprueba requisitos (Windows, virtualizacion, espacio en C:)
#     2. Instala WSL2 y Ubuntu-24.04
#     3. Genera C:\Users\<tu>\.wslconfig ajustado a la RAM y CPU reales
#
#  Que NO hace: no borra nada, no toca el NAS, no instala Docker.
#  Si ya existe un .wslconfig, se guarda copia antes de escribir.
#  Es idempotente: se puede volver a ejecutar sin miedo.
# =============================================================================

$ErrorActionPreference = 'Stop'

function Paso($t)  { Write-Host "`n=== $t ===" -ForegroundColor Cyan }
function OK($t)    { Write-Host "  OK    $t" -ForegroundColor Green }
function Aviso($t) { Write-Host "  AVISO $t" -ForegroundColor Yellow }
function Alto($t)  { Write-Host "  ALTO  $t" -ForegroundColor Red }

# ------------------------------------------------------- 1. Administrador ---
Paso "Comprobando requisitos"
$esAdmin = ([Security.Principal.WindowsPrincipal] [Security.Principal.WindowsIdentity]::GetCurrent()
           ).IsInRole([Security.Principal.WindowsBuiltInRole]::Administrator)
if (-not $esAdmin) {
    Alto "Esta ventana NO es de administrador."
    Write-Host "  Cierra, abre PowerShell con 'Ejecutar como administrador' y vuelve a lanzarlo."
    exit 1
}
OK "sesion de administrador"

# ------------------------------------------------------------- 2. Windows ---
$os = Get-CimInstance Win32_OperatingSystem
$build = [int]$os.BuildNumber
if ($build -lt 19041) {
    Alto "Windows build $build. WSL2 necesita 19041 o superior. Actualiza Windows primero."
    exit 1
}
OK ("Windows build {0}" -f $build)

# ------------------------------------------------------ 3. Virtualizacion ---
$cs  = Get-CimInstance Win32_ComputerSystem
$cpu = Get-CimInstance Win32_Processor | Select-Object -First 1
if (-not $cs.HypervisorPresent -and -not $cpu.VirtualizationFirmwareEnabled) {
    Alto "La virtualizacion no esta activada en la BIOS/UEFI."
    Write-Host "  Reinicia, entra en la BIOS y activa Intel VT-x / AMD-V."
    Write-Host "  Suele estar en Advanced -> CPU Configuration."
    exit 1
}
OK "virtualizacion disponible"

# ---------------------------------------------------------- 4. Espacio C: ---
$c = Get-Volume -DriveLetter C
$libreGB = [math]::Round($c.SizeRemaining / 1GB, 1)
if ($libreGB -lt 60) {
    Aviso "Solo $libreGB GB libres en C:. El stack completo pide unos 60 GB."
    $r = Read-Host "  Continuar de todas formas? (s/N)"
    if ($r -ne 's' -and $r -ne 'S') { Write-Host "  Cancelado."; exit 0 }
} else {
    OK "$libreGB GB libres en C:"
}

# ------------------------------------------------------------ 5. WSL base ---
Paso "Instalando WSL2"
$wsl = "$env:SystemRoot\System32\wsl.exe"
$necesitaReinicio = $false

# Que exista wsl.exe no significa nada: en Windows 11 es un stub que ya viene de
# fabrica. Lo que decide es VirtualMachinePlatform, el unico componente que WSL2
# necesita de verdad.
#
# OJO con 'Microsoft-Windows-Subsystem-Linux': ese componente es solo para WSL1.
# Con el WSL moderno (paquete de la Store, el que instala 'wsl --install') se queda
# en Disabled para siempre y WSL2 funciona igual. Si el script exigiera 'Enabled'
# pediria reinicio en cada pasada y nunca llegaria a instalar Ubuntu.
$featWsl = (Get-WindowsOptionalFeature -Online -FeatureName Microsoft-Windows-Subsystem-Linux).State
$featVmp = (Get-WindowsOptionalFeature -Online -FeatureName VirtualMachinePlatform).State
Write-Host "  Componentes: VirtualMachinePlatform=$featVmp  (WSL1=$featWsl, no hace falta)"

# Segunda senal: que el WSL moderno responda. Si 'wsl --version' falla, falta el paquete.
& $wsl --version 2>$null | Out-Null
$wslModerno = ($LASTEXITCODE -eq 0)

if ($featVmp -ne 'Enabled') {
    Write-Host "  Activando VirtualMachinePlatform (sin instalar todavia ninguna distribucion)..."
    & $wsl --install --no-distribution
    if ($LASTEXITCODE -ne 0) {
        Aviso "wsl --install devolvio $LASTEXITCODE; recurriendo a dism"
        & dism.exe /online /enable-feature /featurename:VirtualMachinePlatform /all /norestart | Out-Null
    }
    $necesitaReinicio = $true
} elseif (-not $wslModerno) {
    Aviso "VirtualMachinePlatform esta activo pero falta el paquete de WSL; instalandolo..."
    & $wsl --install --no-distribution
    if ($LASTEXITCODE -ne 0) { Alto "no he podido instalar el paquete de WSL (codigo $LASTEXITCODE)"; exit 1 }
} else {
    OK "componentes de Windows ya activados"
    Write-Host "  Actualizando el kernel de WSL..."
    & $wsl --update
    if ($LASTEXITCODE -ne 0) { Aviso "wsl --update devolvio $LASTEXITCODE (no bloquea)" }
}

if ($necesitaReinicio) {
    Paso "REINICIO NECESARIO"
    Write-Host "  Se han activado los componentes de Windows. Reinicia el equipo y"
    Write-Host "  vuelve a ejecutar este mismo script para continuar." -ForegroundColor Yellow
    exit 0
}

# Sin '2>&1': en PowerShell 5.1 redirigir el stderr de un .exe genera un
# NativeCommandError que, con ErrorActionPreference='Stop', aborta el script.
& $wsl --set-default-version 2 2>$null
OK "version por defecto: WSL2"

# -------------------------------------------------------------- 6. Ubuntu ---
Paso "Ubuntu 24.04"
$distros = (& $wsl --list --quiet 2>$null | Out-String) -replace "`0", ""
if ($distros -match 'Ubuntu-24\.04') {
    OK "Ubuntu-24.04 ya instalado, no se toca"
} else {
    Write-Host "  Instalando Ubuntu-24.04 (tarda unos minutos)..."
    # --no-launch: descarga y registra la distro sin abrir la ventana de creacion de
    # usuario. Asi el script termina solo y el alta del usuario es un paso aparte y
    # explicito (ver el cierre), en vez de dejar el script colgado en un prompt.
    & $wsl --install -d Ubuntu-24.04 --no-launch
    if ($LASTEXITCODE -ne 0) { Alto "la instalacion de Ubuntu-24.04 devolvio $LASTEXITCODE"; exit 1 }
    OK "Ubuntu-24.04 instalado (falta crear el usuario)"
}

# ----------------------------------------------------------- 7. .wslconfig ---
Paso "Generando .wslconfig"
$ramGB = [math]::Floor($cs.TotalPhysicalMemory / 1GB)
# Reparto segun la RAM real del equipo. En maquinas pequenas Windows necesita
# ~3 GB en reposo; en grandes se le dejan 5 y WSL se queda con el resto.
# Ojo: TotalPhysicalMemory de 7,9 GB redondea a 7, asi que restar 2 es lo que
# deja los 5 GB de WSL / ~3 GB de Windows que fija PLAN.md seccion 3.
if     ($ramGB -ge 16) { $memWsl = $ramGB - 5 }
elseif ($ramGB -ge 12) { $memWsl = $ramGB - 4 }
else                   { $memWsl = [math]::Max(4, $ramGB - 2) }
$swapWsl     = if ($memWsl -lt 8) { 6 } else { 4 }
$procs       = [math]::Max(2, $cpu.NumberOfLogicalProcessors - 1)
$rutaConfig  = Join-Path $env:USERPROFILE '.wslconfig'
if ($memWsl -lt 8) {
    Aviso "con $ramGB GB de RAM, Immich ira SIN machine learning (ver PLAN.md seccion 3)"
}

$contenido = @"
# Generado por 01-instalar-wsl2.ps1 el $(Get-Date -Format 'yyyy-MM-dd HH:mm')
# RAM detectada: ${ramGB} GB | CPU logicas: $($cpu.NumberOfLogicalProcessors)
#
# Sin este fichero WSL2 reclama hasta el 80% de la RAM y Windows empieza a
# paginar justo cuando Immich esta indexando.
# El swap no es un lujo en equipos pequenos: evita que el OOM killer mate Postgres.

[wsl2]
memory=${memWsl}GB
processors=${procs}
swap=${swapWsl}GB

[experimental]
# Devuelve al host la RAM que WSL deja de usar tras un indexado grande.
autoMemoryReclaim=gradual
# El disco virtual devuelve al SSD el espacio que libera (no crece sin parar).
sparseVhd=true
"@

if (Test-Path $rutaConfig) {
    $copia = "$rutaConfig.bak-$(Get-Date -Format 'yyyyMMdd-HHmmss')"
    Copy-Item $rutaConfig $copia
    Aviso "ya existia un .wslconfig - copia guardada en $copia"
}
Set-Content -Path $rutaConfig -Value $contenido -Encoding UTF8
OK "escrito $rutaConfig  (memory=${memWsl}GB, processors=${procs})"

# ------------------------------------------------------------ 8. Cierre ---
Paso "Siguiente paso"
Write-Host "  1. Si Ubuntu acaba de instalarse, crea tu usuario normal (no root):"
Write-Host "        wsl -d Ubuntu-24.04" -ForegroundColor Cyan
Write-Host "     Pedira usuario y contrasena. Apunta ambos: los vas a necesitar en cada 'sudo'." -ForegroundColor Yellow
Write-Host "  2. Cierra todas las ventanas de Ubuntu y ejecuta:  wsl --shutdown"
Write-Host "  3. Vuelve a abrir Ubuntu y lanza:"
Write-Host "        powershell -ExecutionPolicy Bypass -File .\02-configurar-ubuntu.ps1" -ForegroundColor Cyan
Write-Host ""
Write-Host "  Verificacion de la fase 1 (dentro de Ubuntu):"
Write-Host "        systemctl is-system-running     -> running o degraded"
Write-Host "        free -h                         -> total ~${memWsl} GB"
Write-Host "        nproc                           -> ${procs}"
Write-Host ""
