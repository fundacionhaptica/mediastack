# =============================================================================
#  FASE 1 (cierre) - Configurar Ubuntu: systemd + verificacion
#
#  Ejecutar DESPUES de 01-instalar-wsl2.ps1 y de haber creado el usuario de Ubuntu.
#
#  Uso (PowerShell COMO ADMINISTRADOR):
#     cd C:\claude\mediastack\wsl
#     powershell -ExecutionPolicy Bypass -File .\02-configurar-ubuntu.ps1
#
#  Que hace:
#     1. Copia wsl.conf a /etc/wsl.conf dentro de Ubuntu (activa systemd)
#     2. Reinicia WSL
#     3. Verifica: systemd, RAM, nucleos, red y ping al NAS
#
#  Que NO hace: no borra nada. Si ya hay un /etc/wsl.conf, lo respalda antes.
# =============================================================================

$ErrorActionPreference = 'Stop'
$DISTRO = 'Ubuntu-24.04'
$wsl = "$env:SystemRoot\System32\wsl.exe"

function Paso($t)  { Write-Host "`n=== $t ===" -ForegroundColor Cyan }
function OK($t)    { Write-Host "  OK    $t" -ForegroundColor Green }
function Aviso($t) { Write-Host "  AVISO $t" -ForegroundColor Yellow }
function Alto($t)  { Write-Host "  ALTO  $t" -ForegroundColor Red }

$fallos = 0

# ------------------------------------------------------------ 0. Chequeos ---
Paso "Comprobando que Ubuntu esta listo"
# Sin '2>&1': en PowerShell 5.1 redirigir el stderr de un .exe genera un
# NativeCommandError que, con ErrorActionPreference='Stop', aborta el script.
$lista = (& $wsl --list --quiet 2>$null | Out-String) -replace "`0", ""
if ($lista -notmatch [regex]::Escape($DISTRO)) {
    Alto "$DISTRO no aparece instalado. Ejecuta antes 01-instalar-wsl2.ps1"
    exit 1
}
$usuario = (& $wsl -d $DISTRO -- whoami 2>$null | Out-String).Trim()
# Buscamos la cuenta normal (la primera con UID >= 1000) dentro de la distro.
# Nada de '$3' de awk aqui: wsl.exe expande las variables al traducir la linea de
# comandos, aunque vayan entre comillas simples, y el script llega roto a bash.
$busca = 'getent passwd {1000..1010} | head -1 | cut -d: -f1'
$normal = (& $wsl -d $DISTRO -u root -- bash -c $busca 2>$null | Out-String).Trim()
if (-not $normal) {
    Alto "en $DISTRO no existe ninguna cuenta normal, solo root."
    Write-Host "  Creala antes de seguir:"
    Write-Host "        wsl -d $DISTRO -u root -- adduser TU_USUARIO" -ForegroundColor Cyan
    Write-Host "        wsl -d $DISTRO -u root -- usermod -aG sudo TU_USUARIO" -ForegroundColor Cyan
    exit 1
}
if ($usuario -eq 'root') {
    # Normal cuando la distro se instalo con --no-launch: arranca como root hasta que
    # /etc/wsl.conf fija [user] default. Este mismo script copia ese wsl.conf y la
    # verificacion 3.6 comprueba que el cambio ha prendido de verdad.
    Aviso "la distro entra como root; wsl.conf la cambiara a '$normal'"
} else {
    OK "usuario de Ubuntu: $usuario"
}

# ---------------------------------------------------------- 1. /etc/wsl.conf ---
Paso "Activando systemd en Ubuntu"
$origenWin = Join-Path $PSScriptRoot 'wsl.conf'
if (-not (Test-Path $origenWin)) { Alto "no encuentro $origenWin"; exit 1 }

# Ni argumentos ni entrada estandar: el trabajo se escribe en un .sh temporal y bash
# lo lee por su ruta /mnt/c. Los otros dos caminos estan minados en PowerShell 5.1:
#   - por linea de comandos, wsl.exe traduce lo que le pasas y se come los '$' y las
#     '\' aunque vayan entre comillas simples ('$(date)' y 's/\r$//' llegan rotos);
#   - por entrada estandar, PowerShell encabeza con un BOM que bash pega al primer
#     comando ("#: command not found") y remata con CRLF.
# El fichero se escribe en UTF-8 sin BOM y con saltos LF, que es lo que espera bash.
$contenido = ((Get-Content $origenWin -Raw -Encoding UTF8) -replace "`r`n", "`n").TrimEnd("`n")
$script = @"
exec 2>&1
if [ -f /etc/wsl.conf ]; then cp /etc/wsl.conf /etc/wsl.conf.bak-`$(date +%Y%m%d-%H%M%S); fi
cat > /etc/wsl.conf <<'FIN_WSL_CONF'
$contenido
FIN_WSL_CONF
cat /etc/wsl.conf
"@

$tmpWin = Join-Path $env:TEMP "mediastack-wslconf-$(Get-Date -Format 'yyyyMMddHHmmss').sh"
[IO.File]::WriteAllText($tmpWin, ($script -replace "`r`n", "`n") + "`n",
                        (New-Object System.Text.UTF8Encoding $false))
# C:\Users\...\x.sh  ->  /mnt/c/Users/.../x.sh  (sin backslashes, que wsl.exe si respeta)
$tmpLinux = '/mnt/' + $tmpWin.Substring(0,1).ToLower() + ($tmpWin.Substring(2) -replace '\\', '/')
try {
    $res = & $wsl -d $DISTRO -u root -- bash $tmpLinux 2>$null | Out-String
    $codigo = $LASTEXITCODE
} finally {
    Remove-Item $tmpWin -ErrorAction SilentlyContinue
}
if ($codigo -ne 0) { Alto "no se ha podido escribir /etc/wsl.conf:`n$res"; exit 1 }
OK "/etc/wsl.conf escrito"
Write-Host ($res.Trim() -split "`n" | ForEach-Object { "        $_" }) -Separator "`n"

# ------------------------------------------------------------ 2. Reinicio ---
Paso "Reiniciando WSL para aplicar los cambios"
& $wsl --shutdown
Start-Sleep -Seconds 8
& $wsl -d $DISTRO -- true 2>$null | Out-Null
Start-Sleep -Seconds 5
OK "WSL reiniciado"

# -------------------------------------------------------- 3. VERIFICACION ---
Paso "VERIFICACION FASE 1"

# 3.1 version 2
$verbose = (& $wsl --list --verbose 2>$null | Out-String) -replace "`0", ""
$linea = ($verbose -split "`n" | Where-Object { $_ -match [regex]::Escape($DISTRO) }) -join ''
if ($linea -match '\s2\s*$' -or $linea -match '\s2\s') { OK "$DISTRO corriendo en WSL version 2" }
else { Alto "no confirmo que sea WSL2: $($linea.Trim())"; $fallos++ }

# 3.2 systemd  (is-system-running devuelve codigo != 0 si esta 'degraded': solo miramos el texto)
$systemd = (& $wsl -d $DISTRO -- systemctl is-system-running 2>$null | Out-String).Trim()
if ($systemd -match 'running|degraded|starting') { OK "systemd activo ($systemd)" }
else { Alto "systemd NO activo ($systemd). Sin esto Docker no arrancara solo"; $fallos++ }

# 3.3 RAM  (leemos /proc/meminfo y parseamos en PowerShell: nada de awk por la
# linea de comandos, ver el comentario del paso 1)
$memRaw  = (& $wsl -d $DISTRO -- head -1 /proc/meminfo 2>$null | Out-String)
$memKb   = if ($memRaw -match '(\d+)') { [int]$Matches[1] } else { 0 }
$mem     = [math]::Round($memKb / 1048576, 1)
$ramHost = [math]::Floor((Get-CimInstance Win32_ComputerSystem).TotalPhysicalMemory / 1GB)
Write-Host "        RAM visible en WSL: $mem GB   (host: $ramHost GB)"
if ($mem -gt 0 -and $mem -lt ($ramHost - 1)) {
    OK "el limite del .wslconfig se esta aplicando"
} else {
    Alto "WSL ve casi toda la RAM del equipo: el .wslconfig no se ha aplicado"
    Write-Host "        Revisa que exista $env:USERPROFILE\.wslconfig y repite 'wsl --shutdown'"
    $fallos++
}

# 3.4 nucleos
$nproc = (& $wsl -d $DISTRO -- nproc | Out-String).Trim()
OK "nucleos disponibles en WSL: $nproc"

# 3.5 red y NAS desde dentro de WSL (miramos el codigo de salida del ping, sin shell)
& $wsl -d $DISTRO -- ping -c 2 -W 3 192.168.1.205 2>$null | Out-Null
if ($LASTEXITCODE -eq 0) { OK "el NAS 192.168.1.205 responde desde dentro de WSL" }
else { Aviso "el NAS no responde desde WSL - se revisara en la fase 3" }

# 3.6 usuario por defecto (el [user] default de wsl.conf)
$quien = (& $wsl -d $DISTRO -- whoami 2>$null | Out-String).Trim()
if ($quien -and $quien -ne 'root') { OK "la distro entra como '$quien', no como root" }
else { Alto "la distro sigue entrando como root: revisa [user] default en wsl.conf"; $fallos++ }

# ---------------------------------------------------------------- Cierre ---
Write-Host ""
if ($fallos -eq 0) {
    Write-Host "FASE 1 VERIFICADA - 0 fallos" -ForegroundColor Green
    Write-Host ""
    Write-Host "Siguiente: FASE 2 (Docker Engine dentro de WSL). Dentro de Ubuntu:"
    Write-Host "    curl -fsSL https://get.docker.com | sudo sh" -ForegroundColor Cyan
    Write-Host "    sudo usermod -aG docker `$USER" -ForegroundColor Cyan
    Write-Host "    sudo systemctl enable --now docker" -ForegroundColor Cyan
} else {
    Write-Host "FASE 1 CON $fallos FALLO(S) - no avances a la fase 2 hasta resolverlos" -ForegroundColor Red
}
Write-Host ""
