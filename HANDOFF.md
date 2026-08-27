# HANDOFF — estado del despliegue a 2026-08-27

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
| 3 Montajes NAS | ⛔ bloqueada | NFS sigue apagado en el NAS (ver abajo) |
| 4 Repo en git | ✅ | GitHub `fundacionhaptica/mediastack`, al día con `main` |
| 5 Immich | ⏸ preparada | ficheros, `.env` e **imágenes ya descargadas**; depende de la fase 3 |
| 6 Arranque automático | ⏸ preparada | script listo; falta ejecutarlo en PowerShell elevado |
| 7 Navidrome/Jellyfin | ⏸ preparada | `.env` e **imágenes ya descargadas**; dependen de la fase 3 |
| 9 Acceso desde fuera | ⏸ preparada | Tailscale + Caddy + portal escritos; runbook en PASOS.md §9 |

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
- `/mnt/nas/{fotos,fotos-historico,musica,video,backups}` creados y **vacíos**.
- Paquetes instalados en Ubuntu: `nfs-common`, `cifs-utils`, `smbclient` (los dos últimos
  para poder tirar por el plan B sin esperas).
- **Imágenes Docker ya descargadas** (~6,9 GB): `immich-server:v3`, `immich-app/postgres`,
  `valkey/valkey:9`, `deluan/navidrome`, `jellyfin/jellyfin`. Al desbloquear la fase 3, los
  `docker compose up -d` arrancan sin descargar nada.
- Git: `C:\claude\mediastack` tiene el remoto `github`; `~/mediastack` tiene `origin` →
  GitHub y `windows` → `/mnt/c/claude/mediastack`. El flujo es: **editar en
  `C:\claude\mediastack` → commit → push a github → `git -C ~/mediastack pull`**.

---

## Bloqueo real que queda: NFS apagado en el NAS → fases 3, 5 y 7

Comprobado desde WSL el 2026-08-27: el NAS responde al ping, **445 (SMB) abierto**, pero
**2049 y 111 cerrados** y `showmount -e 192.168.1.205` da `clnt_create: RPC: Unable to
receive`. Exactamente igual que hace dos días.

**Elegida por Jaime el 2026-08-27: opción A.** Va a encender NFS en DSM; hasta entonces las
fases 3, 5 y 7 siguen paradas. La opción B queda como plan B ya preparado, por si NFS da los
problemas de permisos típicos de Synology.

**Opción A (la del plan, elegida).** En DSM: *Panel de control → Servicios de archivos →
NFS → Habilitar*, máximo **NFSv4.1**, y los permisos NFS por carpeta que detalla `PASOS.md`
fase 3 (solo lectura para música, vídeo e histórico; lectura/escritura solo para la carpeta de
subidas de Immich).

**Opción B (plan B, ya preparado).** SMB está abierto: se puede montar por CIFS con la
variante B de `wsl/fstab.snippet`. Rinde peor con muchos ficheros pequeños, pero desbloquea
todo hoy mismo. Hace falta usuario y contraseña de un usuario del NAS.

Al volver, lo primero — como root:

```bash
wsl -d Ubuntu-24.04 -u root -- /home/jaime/mediastack/scripts/montar-nas.sh diagnostico
```

### Pendiente de dato: los nombres reales de las carpetas compartidas

`wsl/fstab.snippet` asume `/volume1/foto`, `/volume1/foto-historico`, `/volume1/music`,
`/volume1/video`, pero **eso no está verificado** — la fase 0 no llegó a inventariar el NAS.
Se resuelve en un comando:

```bash
wsl -d Ubuntu-24.04 -u root -- /home/jaime/mediastack/scripts/montar-nas.sh listar-smb <usuario-del-NAS>
```

---

## Ya no es un bloqueo: `sudo` sin contraseña

`jaime` se creó con `--disabled-password`, así que `sudo` desde dentro pide una contraseña que
no existe. **Se puede escalar sin arreglarlo**, incluso desde una sesión de WSL, porque el
interop de Windows funciona:

```bash
/mnt/c/Windows/System32/wsl.exe -d Ubuntu-24.04 -u root -- <comando>   # → uid=0
```

Aun así conviene ponerle contraseña alguna vez:

```powershell
wsl -d Ubuntu-24.04 -u root passwd jaime
```

---

## Siguiente paso una vez desbloqueado

```bash
# FASE 3 — probar a mano ANTES de tocar /etc/fstab (el script monta, enseña y desmonta)
wsl -d Ubuntu-24.04 -u root -- /home/jaime/mediastack/scripts/montar-nas.sh probar-nfs /volume1/foto
#   o, por el plan B:
wsl -d Ubuntu-24.04 -u root -- /home/jaime/mediastack/scripts/montar-nas.sh probar-cifs foto jaime
# si se lee: poner la variante que toque de wsl/fstab.snippet en /etc/fstab,
#            systemctl daemon-reload && mount -a

# FASE 5 — Immich (todo preparado e imágenes descargadas)
cd ~/mediastack/immich && docker compose up -d && docker compose logs -f immich-server

# FASE 7 — el resto
cd ~/mediastack/navidrome && docker compose up -d
cd ~/mediastack/jellyfin  && docker compose up -d

bash ~/mediastack/scripts/verificar.sh   # tiene que salir 0 fallos
```

## Fase 6 — cuando el stack esté en verde

En **PowerShell elevado** en el mini PC (el script comprueba la elevación y aborta si no):

```powershell
powershell -ExecutionPolicy Bypass -File C:\claude\mediastack\wsl\06-arranque-automatico.ps1
```

Registra la tarea `MediaStack` (al inicio, como SYSTEM) que llama a
`scripts/boot-mediastack.sh`: ese espera a dockerd, baja a `jaime` y ejecuta
`arrancar-stack.sh`, dejando log en `/var/log/mediastack-boot.log`. Faltan además las dos
piezas manuales: **BIOS → Restore on AC Power Loss = Power On**, y la verificación de verdad,
que es un reinicio en frío.

---

## Fase 9 — el túnel ya está montado; decidido sacar Jellyfin de él

Túnel **MiniPC_Jaime** (Cloudflare Zero Trust, cuenta `synology-maja`):

| Hostname | Servicio | Puerto local | Estado |
|---|---|---|---|
| fotos.ruizespana.com | Immich | localhost:2283 | se queda en el túnel |
| musica.ruizespana.com | Navidrome | localhost:4533 | se queda en el túnel |
| pelis.ruizespana.com | Jellyfin | localhost:8096 | **a retirar del túnel** |

**Decisión de Jaime (2026-08-27): se quita `pelis.ruizespana.com` del túnel.** Se confirma lo
que ya decía `PLAN.md` §6: servir streaming de vídeo por el proxy gratuito de Cloudflare es
zona gris de sus términos, y el límite de 100 MB por petición rompe la subida de vídeos desde
la app de Immich. Jellyfin va por Tailscale.

**Ya está escrito y listo para ejecutar** (runbook completo en `PASOS.md` fase 9):

- `wsl/09-tailscale.sh` — instala Tailscale **dentro de Ubuntu**, no en Windows, y explica por
  qué. Prerrequisitos comprobados el 2026-08-27: `/dev/net/tun`, `ip_forward=1`, systemd
  `running`.
- `caddy/` — reverse proxy que escucha **solo en la IP del tailnet** y da HTTPS válido por
  DNS-01 contra Cloudflare, sin abrir un puerto a Internet. La imagen se compila
  (`caddy/Dockerfile`) porque la oficial no trae el proveedor DNS de Cloudflare.
  Sirve `pelis`, `fotos-vpn` y `casa`.
- `homepage/` — portal de entrada en `casa.ruizespana.com`, con las tres apps y el widget de
  recursos (útil con el presupuesto de RAM de `PLAN.md` §3).
- `PLAN.md` §6 actualizado: el nombre pasa a ser `pelis.` (era `videos.`), se añade `casa.`, y
  se documenta el detalle que rompía la idea — **un registro DNS apunta a una IP, no a un
  puerto**, de ahí Caddy.

Lo que hace falta de tu parte, en este orden:

1. **Borrar `pelis.ruizespana.com` del túnel** en Zero Trust → Networks → Tunnels →
   MiniPC_Jaime. Es justo el tráfico que no queremos por el proxy.
2. Ejecutar `wsl/09-tailscale.sh` y autenticar con `tailscale up --hostname=minipc-jrh`.
3. Tres registros **A en nube GRIS** (`pelis`, `fotos-vpn`, `casa`) → la IP `100.x.y.z`.
4. Un **token de API de Cloudflare** acotado a la zona (`Zone:DNS:Edit`) en `caddy/.env`.

Nada de esto se levanta hasta que el stack esté verde en LAN, o sea, hasta el NFS.

Además, el contenedor `cloudflared` del mini PC **todavía no está levantado** y
`cloudflared/.env` con `TUNNEL_TOKEN` no existe: hasta que el stack no esté verificado en LAN
no se levanta (así lo dice el propio compose).

---

## Trampas ya pagadas (no volver a tropezar)

- **`Microsoft-Windows-Subsystem-Linux` se queda en `Disabled` para siempre**: solo hace falta
  para WSL1. El componente que importa es `VirtualMachinePlatform`. Exigir el primero hacía
  que `01-instalar-wsl2.ps1` pidiera reinicio en bucle.
- **No pasar scripts a `wsl.exe` por argumentos ni por la entrada estándar** desde
  PowerShell 5.1: se come los `$` y las `\` de la línea de comandos aunque vayan entre comillas
  simples (`$(date)`, `awk '$3'`, `s/\r$//`, rutas `C:\...`), y por stdin mete un BOM y remata
  con CRLF. Escribir un `.sh` en UTF-8 sin BOM y ejecutarlo por su ruta, como hacen
  `02-configurar-ubuntu.ps1` y la tarea programada de la fase 6.
- **`2>&1` sobre un `.exe` en PowerShell 5.1** con `$ErrorActionPreference='Stop'` aborta el
  script por `NativeCommandError` aunque el comando haya ido bien. Usar `2>$null`.
- El driver de almacenamiento de Docker 29 se llama **`overlayfs`**, no `overlay2`.
- `docker inspect` de un contenedor inexistente deja un salto de línea en la salida: sin
  limpiarlo, `verificar.sh` reportaba `estado '\nausente'`. Ya corregido.
- La salida de `wsl.exe` llamado **desde dentro de WSL** viene en UTF-16 con NULs: pasarla por
  `tr -d '\0'` o no se puede grepear.

---

## Estado de `scripts/verificar.sh`

7 fallos, y son exactamente los de las fases pendientes: 4 montajes del NAS y 3 puertos HTTP de
contenedores que aún no existen. Entorno WSL, Docker y las reglas de almacenamiento (Postgres
en ext4 local) salen en verde.
