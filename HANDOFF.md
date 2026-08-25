# HANDOFF — estado del despliegue a 2026-08-25

Documento de traspaso: lo que está hecho, lo que está bloqueado y el siguiente comando
exacto. Quien retome esto no necesita el historial de ninguna conversación previa.

Máquina: **MINIPC-JRH**, 192.168.1.227 (Windows 11, Intel N150, 7,9 GB).
NAS: **192.168.1.205**. Repo en Windows: `C:\claude\mediastack`. Copia en WSL: `~/mediastack`.

---

## Hecho y verificado

| Fase | Estado | Detalle |
|---|---|---|
| 0 Inventario | ✅ | `wsl/inventario.txt` |
| 1 WSL2 + Ubuntu | ✅ 0 fallos | WSL 2.7.12, Ubuntu-24.04, systemd `running`, usuario `jaime` |
| 2 Docker | ✅ | Engine 29.7.2 + compose v5.5.0, `enabled` y `active`, driver `overlayfs` |
| 3 Montajes NAS | ⛔ bloqueada | NFS apagado en el NAS (ver abajo) |
| 4 Repo en git | ⚠️ parcial | repo local creado; falta el remoto en GitHub |
| 5 Immich | ⏸ preparada | ficheros y `.env` listos; **sin arrancar**, depende de la fase 3 |
| 6 Arranque automático | ⏳ | pendiente; necesita PowerShell elevado |
| 7 Navidrome/Jellyfin | ⏸ preparada | `.env` listos; **sin arrancar**, dependen de la fase 3 |

Configuración que ya está puesta:

- `C:\Users\Admin\.wslconfig`: `memory=5GB`, `processors=3`, swap ~7,8 GB (en bytes; lo
  cambió el equipo por fuera y se deja así a propósito). WSL ve 4,8 GB de los 7,9 del host.
- `/etc/wsl.conf` (dentro de Ubuntu): systemd, `[user] default=jaime`, automount con metadata.
- Usuario `jaime` (uid 1000) en los grupos `sudo`, `users` y `docker`.
- Datos locales en ext4, ya creados y con dueño `jaime`:
  `/var/lib/mediastack/{immich/postgres,navidrome/data,jellyfin/{config,cache}}`.
- `~/mediastack/immich/`: los tres YAML oficiales de la release descargados (no versionados)
  y `.env` con `DB_PASSWORD` generada, permisos 600. `docker compose config` fusiona bien:
  3 servicios (`database`, `redis`, `immich-server`), Postgres en
  `/var/lib/mediastack/immich/postgres`, biblioteca externa en `/mnt/nas/fotos-historico`.
- `~/mediastack/{navidrome,jellyfin}/.env` con `PUID=1000`, `PGID=1000`, `TZ=Europe/Madrid`.
- `/mnt/nas/{fotos,fotos-historico,musica,video,backups}` creados y **vacíos**, `nfs-common`
  instalado.

---

## Bloqueos (los dos son de Jaime, no se pueden automatizar desde aquí)

### 1. NFS apagado en el NAS → bloquea las fases 3, 5 y 7

Comprobado desde WSL: el NAS responde al ping, **445 (SMB) abierto**, pero **2049 y 111
cerrados** y `showmount -e 192.168.1.205` da `clnt_create: RPC: Unable to receive`.

En DSM: *Panel de control → Servicios de archivos → NFS → Habilitar*, máximo **NFSv4.1**, y
los permisos NFS por carpeta que detalla `PASOS.md` fase 3 (solo lectura para música, vídeo e
histórico; lectura/escritura solo para la carpeta de subidas de Immich).

Al volver, lo primero:

```bash
wsl -d Ubuntu-24.04 -- showmount -e 192.168.1.205
```

Si responde, seguir por la sección "En WSL" de la fase 3.

### 2. `jaime` no tiene contraseña → `sudo` no funciona

La cuenta se creó con `--disabled-password` (la distro se instaló con `--no-launch`, sin el
asistente). Arreglo, una vez:

```powershell
wsl -d Ubuntu-24.04 -u root passwd jaime
```

Mientras tanto, lo que necesita root se hace con `wsl -d Ubuntu-24.04 -u root -- ...`.

---

## Siguiente paso una vez desbloqueado

```bash
# FASE 3 — montar a mano ANTES de tocar /etc/fstab
sudo mount -t nfs -o vers=4.1,soft,timeo=150 192.168.1.205:/volume1/foto /mnt/nas/fotos-historico
ls /mnt/nas/fotos-historico | head
# si se lee: desmontar, poner wsl/fstab.snippet en /etc/fstab, systemctl daemon-reload && mount -a

# FASE 5 — Immich (ya está todo preparado, solo falta levantarlo)
cd ~/mediastack/immich && docker compose up -d && docker compose logs -f immich-server

# FASE 7 — el resto
cd ~/mediastack/navidrome && docker compose up -d
cd ~/mediastack/jellyfin  && docker compose up -d

bash ~/mediastack/scripts/verificar.sh   # tiene que salir 0 fallos
```

Fase 4, para cerrarla: crear el repo en GitHub y
`git -C /mnt/c/claude/mediastack remote add github <url> && git push -u github main`.
Hoy `~/mediastack` clona del repo de Windows (`origin = /mnt/c/claude/mediastack`), así que la
regla de "editar en el repo y hacer `pull` en el mini PC" ya se cumple: se edita en
`C:\claude\mediastack`, se commitea, y en WSL `git -C ~/mediastack pull`.

---

## Trampas ya pagadas (no volver a tropezar)

- **`Microsoft-Windows-Subsystem-Linux` se queda en `Disabled` para siempre**: solo hace falta
  para WSL1. El componente que importa es `VirtualMachinePlatform`. Exigir el primero hacía
  que `01-instalar-wsl2.ps1` pidiera reinicio en bucle.
- **No pasar scripts a `wsl.exe` por argumentos ni por la entrada estándar** desde
  PowerShell 5.1: se come los `$` y las `\` de la línea de comandos aunque vayan entre comillas
  simples (`$(date)`, `awk '$3'`, `s/\r$//`, rutas `C:\...`), y por stdin mete un BOM y remata
  con CRLF. Escribir un `.sh` en UTF-8 sin BOM y ejecutarlo por su ruta `/mnt/c/...`, como hace
  `02-configurar-ubuntu.ps1`.
- **`2>&1` sobre un `.exe` en PowerShell 5.1** con `$ErrorActionPreference='Stop'` aborta el
  script por `NativeCommandError` aunque el comando haya ido bien. Usar `2>$null`.
- El driver de almacenamiento de Docker 29 se llama **`overlayfs`**, no `overlay2`.
- `docker inspect` de un contenedor inexistente deja un salto de línea en la salida: sin
  limpiarlo, `verificar.sh` reportaba `estado '\nausente'`. Ya corregido.

---

## Estado de `scripts/verificar.sh`

Los fallos que quedan son exactamente los de las fases pendientes: 4 montajes del NAS y 3
puertos HTTP de contenedores que aún no existen. Entorno WSL, Docker y las reglas de
almacenamiento (Postgres en ext4 local) salen en verde.
