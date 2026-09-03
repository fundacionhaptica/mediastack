# HANDOFF — estado del despliegue a 2026-09-02

Documento de traspaso: lo que está hecho, lo que está bloqueado y el siguiente comando
exacto. Quien retome esto no necesita el historial de ninguna conversación previa.

Máquina: **MINIPC-JRH**, 192.168.1.227 (Windows 11, Intel N150, 7,9 GB).
NAS: **192.168.1.205**. Repo de trabajo: **`~/mediastack` dentro de WSL**.
`C:\claude\mediastack` está congelada y se borrará al terminar la instalación (CLAUDE.md §2).

---

## Hecho y verificado

| Fase | Estado | Detalle |
|---|---|---|
| 0 Inventario | ✅ | `wsl/inventario.txt` |
| 1 WSL2 + Ubuntu | ✅ 0 fallos | WSL 2.7.12, Ubuntu-24.04, systemd `running`, usuario `jaime` |
| 2 Docker | ✅ | Engine 29.7.2 + compose v5.5.0, `enabled` y `active`, driver `overlayfs` |
| 3 Montajes NAS | ✅ | 4 montajes en `/etc/fstab`, verificados y con los modos correctos |
| 4 Repo en git | ✅ | GitHub `fundacionhaptica/mediastack`, al día con `main` |
| 5 Immich | ✅ | los tres contenedores `healthy`; falta el asistente inicial y la biblioteca externa |
| 6 Arranque automático | 🔶 casi | tarea registrada y probada; **BIOS y reinicio en frío aplazados a propósito** |
| 7 Navidrome/Jellyfin | ✅ | los dos `healthy` y el backup diario de la BBDD en cron |
| 8b LAN (modo espejo) | ❌ descartada | rompe los montajes NFS. Revertida de verdad el 2026-09-03 |
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
- Git, **desde el 2026-09-01**: la copia que commitea es `~/mediastack` (remoto `origin` →
  GitHub). El flujo es **editar en WSL → commit → push**, sin intermediarios.
  `C:\claude\mediastack` (remoto `github`, y el remoto `windows` de la copia de WSL que
  apunta a ella) queda congelada hasta que Jaime la borre.

  **Borrarla no rompe el arranque automático**, que es el miedo razonable: la tarea programada
  de la fase 6 ejecuta `C:\Windows\System32\wsl.exe` con `/home/jaime/mediastack/scripts/boot-mediastack.sh`
  — una ruta de dentro de WSL. Comprobado en `wsl/06-arranque-automatico.ps1`. Lo que sí hay
  que mirar antes de borrar es que no queden cambios sin subir:
  `git -C /mnt/c/claude/mediastack status`.

---

## Fase 3 — resuelta, con dos hallazgos que conviene no olvidar

### Hallazgo 1 — NFSv3 con `nolock`, y no es negociable

Con `vers=4.1` (lo que decía el plan) el mount se cuelga hasta el timeout, o monta y entonces
el primer `ls` se cuelga. Con `vers=3,nolock` monta en **1 segundo**.

La causa: el bloqueo de ficheros de NFS necesita que el **servidor llame de vuelta al
cliente** — NLM/statd en v3, callbacks de delegación en v4. WSL2 sale por **NAT detrás de
Windows**, así que el cliente anuncia `clientaddr=172.18.x.x` y el NAS no puede alcanzarlo
jamás. El razonamiento completo está en `wsl/fstab.snippet`.

Es seguro renunciar al locking **aquí**: nada que lo necesite escribe en el NAS. Postgres,
SQLite y la config de Jellyfin viven en ext4 local (CLAUDE.md §5); sobre el NAS solo hay
lecturas y las subidas de Immich, con un único escritor.

### Hallazgo 2 — los nombres reales no eran los que suponía el plan

`photo` (no `foto`), `Media` con M mayúscula, y `video` en minúscula. `wsl/fstab.snippet` daba
por buenas rutas que nadie había verificado; ya lleva las reales.

### Montajes en producción

| Punto de montaje | Origen | Modo | Para qué |
|---|---|---|---|
| `/mnt/nas/fotos` | `/volume1/Media` | `rw` | subidas nuevas de Immich (`UPLOAD_LOCATION`) |
| `/mnt/nas/fotos-historico` | `/volume1/photo` | `ro` | biblioteca externa de Immich |
| `/mnt/nas/musica` | `/volume1/music` | `ro` | Navidrome |
| `/mnt/nas/video` | `/volume1/video` | `ro` | Jellyfin |

En `/etc/fstab` con `nofail` y `x-systemd.automount`; hay copias previas en `/etc/fstab.bak-*`.
`homes` ya no se exporta. **`verificar.sh` sale con 0 fallos.**

---

## Lo que queda

### 1. ~~Permisos de `Media`~~ y ~~carpeta de backups~~ — resueltos el 2026-08-27

El squash de `Media` se cambió a **«Asignar todos los usuarios a admin»**, y los volcados van a
`/volume1/Media/backup-immich` (decisión de Jaime: una subcarpeta del mismo recurso, en vez de
una carpeta compartida nueva). `scripts/backup-immich-db.sh` ya apunta ahí, hace volcados de
**18 MB** y está en el cron de `jaime`:

```
30 0 * * * /home/jaime/mediastack/scripts/backup-immich-db.sh >> /home/jaime/immich-backup.log 2>&1
```

### 2. ⚠️ Cambiar el squash de un recurso NFS deja ficheros huérfanos

Cambiar el squash **con Immich ya arrancado** lo metió en un bucle de reinicio. Merece la pena
entenderlo, porque volverá a pasar si se toca el squash de nuevo:

1. Immich crea un fichero marcador `.immich` (13 bytes) en cada una de sus seis carpetas —
   `thumbs`, `upload`, `backups`, `library`, `profile`, `encoded-video` — y **anota en su base
   de datos** que esas carpetas ya están verificadas. Es su protección para no escribir en un
   volumen desmontado.
2. Los marcadores se crearon cuando root mapeaba a root, así que quedaron de `uid 0` con modo
   644. Tras el cambio de squash, el contenedor (que corre como root) pasa a mapear a `admin`,
   y `admin` no puede escribir un fichero de `uid 0` → `EACCES` → reinicio en bucle.
3. `chown` y `chmod` **tampoco valen**: `admin` no es root en el NAS, da `Operation not
   permitted`.
4. Borrar los marcadores no basta: como la BBDD dice que ya estaban verificados, el error pasa
   de `EACCES` a `ENOENT` y sigue sin arrancar.

La salida, en este orden:

```bash
# 1. arrancar una sola vez saltándose la comprobación (fichero temporal, se borra después)
#    services: immich-server: environment: [IMMICH_IGNORE_MOUNT_CHECK_ERRORS=true]
# 2. recrear los seis marcadores como root, que ahora mapea a admin:
for d in thumbs upload backups library profile encoded-video; do
  printf '%s' "$(date +%s%3N)" > "/mnt/nas/fotos/$d/.immich"; chmod 0666 "/mnt/nas/fotos/$d/.immich"
done
# 3. quitar el fichero temporal y  docker compose up -d --force-recreate immich-server
```

Documentación de Immich: docs.immich.app/administration/system-integrity#folder-checks

### 3. Asistentes iniciales, a mano en el navegador

**En el navegador del propio mini PC**, con `localhost`: desde otro equipo de la LAN estos
puertos no responden (ver «Estado a 2026-09-01» al final de este documento).

- **Immich** `http://localhost:2283` — crear el usuario admin y, en *Administración →
  Bibliotecas externas*, añadir `/mnt/nas/fotos-historico`.
- **Jellyfin** `http://localhost:8096` — asistente, y bibliotecas apuntando a `/media`
  (la ruta **dentro** del contenedor, no la de WSL).
- **Navidrome** `http://localhost:4533` — crear usuario. Ya tiene 276+ canciones.

### 4. Vigilar la memoria de `immich_server`

El `mem_limit` se subió de 1,5 a **2,0 GB** el 2026-08-27, y con eso se asentó en el **42%**.
Los 500 MB extra salieron del margen que WSL ya tenía; `.wslconfig` no se tocó. Con los cinco
contenedores en marcha, WSL usa 2,0 GB de 4,8. Sigue mereciendo la pena mirarlo durante el
primer escaneo del histórico, que es cuando más aprieta:

```bash
docker stats --no-stream
docker inspect immich_server --format 'OOMKilled={{.State.OOMKilled}}'
```

Si lo mata el OOM, subir `mem_limit` en `immich/docker-compose.override.yml` — hay ~2,4 GB
disponibles en WSL — y actualizar el presupuesto de `PLAN.md` §3 en el mismo commit.

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

## Siguiente paso: el trabajo se retoma DESDE el mini PC

Decisión de Jaime, 2026-09-01. Las sesiones de Claude Code en la nube pueden llevar el repo,
pero no alcanzan esta máquina: no están en la LAN y no conservan nada entre sesiones. Se
descartaron SSH abierto a Internet y un MCP de ejecución de comandos por el túnel — demasiada
superficie nueva en la máquina donde viven las fotos. Se instala Claude Code **dentro de
Ubuntu/WSL**: instrucciones en `PASOS.md`, sección «Instalar Claude Code dentro de Ubuntu».

Las fases 3, 5 y 7 están cerradas: los cinco contenedores arrancan y `verificar.sh` salió con
**0 fallos** el 2026-08-28. Lo que queda, en este orden:

1. **Asistentes iniciales** (Immich, Jellyfin, Navidrome) — «Lo que queda» §3. Sin usuarios no
   hay nada que publicar hacia fuera, así que va primero. Se hacen en el navegador del propio
   mini PC contra `localhost`: desde otro equipo de la LAN esos puertos no responden, y tras
   descartarse el modo espejo (2026-09-02) siguen sin responder.
2. **Cerrar la fase 6**: BIOS *Restore on AC Power Loss = Power On* y el reinicio en frío.
   Ya no depende de la 8b: la verificación de `PASOS.md` §6 se reescribió para hacerse con
   marcas de tiempo dentro del propio mini PC, sin `curl` desde la LAN.
3. **Fase 9 entera**: `PASOS.md` §9, pasos 9a → 9e. Es lo que da acceso de verdad —
   por Tailscale y por la VM de Oracle— y no necesita que la LAN vea WSL.
4. **Acceso desde la LAN: abierto, sin vía elegida.** La 8b (modo espejo) está descartada por
   experimento. Las demás opciones de `PLAN.md` §6 siguen en pie. No bloquea nada de lo
   anterior; si se retoma, lo que se juega es el NFS.

Antes de nada, en la sesión que se abra en el mini PC:

```bash
git -C ~/mediastack pull
bash ~/mediastack/scripts/verificar.sh     # foto real del estado, que desde fuera no se puede
```

Para arrancar el stack a mano si hiciera falta:

```powershell
wsl -d Ubuntu-24.04 -u root -- /home/jaime/mediastack/scripts/boot-mediastack.sh
```

## Fase 6 — hecha a medias, y el resto aplazado a propósito

La tarea **`MediaStack`** está registrada y probada el 2026-08-28: corre como `Admin` con
`LogonType S4U` y `RunLevel Highest`, disparador al inicio con 30 s de margen, y termina con
`LastTaskResult: 0`. La cadena entera (root → espera a `dockerd` → baja a `jaime` →
`arrancar-stack.sh`) queda registrada en `/var/log/mediastack-boot.log`.

⚠️ **Pendiente, aplazado por Jaime el 2026-08-28. Hasta que se haga, el arranque automático NO
está garantizado:**

1. **BIOS/UEFI → *Restore on AC Power Loss = Power On***. Sin esto, tras un corte de luz el
   mini PC no se enciende siquiera, y la tarea programada da igual.
2. **Reinicio en frío**, la única prueba que vale. Reiniciar, esperar 5 minutos sin tocar el
   teclado ni iniciar sesión, y comprobar por marcas de tiempo que el stack ya estaba en pie
   antes de que iniciaras sesión — el runbook actualizado está en `PASOS.md` §6. **No** sirve
   `curl` desde otro equipo de la LAN: esos puertos no salen de WSL.

Mientras tanto, si el equipo se apaga, el stack se levanta con:

```powershell
wsl -d Ubuntu-24.04 -u root -- /home/jaime/mediastack/scripts/boot-mediastack.sh
```

### Por qué la tarea no puede correr como SYSTEM

Las distribuciones de WSL se registran **por usuario de Windows**, en `HKCU\...\Lxss`.
Comprobado: `Ubuntu-24.04` cuelga del perfil de `Admin` y la rama de `S-1-5-18` está vacía. Una
tarea como SYSTEM lanzaría `wsl.exe` sin encontrar ninguna distribución, y fallaría **en
silencio** en cada arranque.

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

### Actualización 2026-08-31 — `pelis.` y `fotos-vpn.` pasan de Tailscale-only a públicas

Motivo: hace falta compartir contenido (p. ej. el material de un evento) con gente que no va a
instalarse Tailscale. Exigir tailnet para eso no vale. **Decisión de Jaime: montar un Caddy
propio en una VM Oracle Cloud Always Free (IP pública), que reenvía por Tailscale al mini PC —
la VM se deja siempre encendida (Always Free no cobra por eso).** Sigue evitando los dos avisos
de Cloudflare (§6) porque no hay proxy de Cloudflare de por medio, solo DNS apuntando a un
servidor propio.

Queda escrito y listo para ejecutar en `oracle-vps/` (README con el paso a paso de la consola de
OCI, `setup.sh`, `docker-compose.yml` y `Caddyfile`). Se han actualizado en consecuencia:
`caddy/Caddyfile` del mini PC (ya no sirve `pelis.`/`fotos-vpn.`, solo `casa.`),
`cloudflared/docker-compose.yml` (comentario con los hostnames públicos) y `PLAN.md` §6.

Pendiente, de la parte de Jaime (nada de esto se puede hacer desde este repo, requiere la
consola de Oracle Cloud y credenciales suyas):

1. Crear la instancia Always Free en `cloud.oracle.com` (`oracle-vps/README.md` paso 1).
2. Abrir 80/443 en el Security List de la VCN — capa de firewall de la nube, aparte del `ufw`
   que instala `setup.sh` en la propia VM.
3. `ssh` a la VM, clonar el repo, correr `oracle-vps/setup.sh` con un `TAILSCALE_AUTHKEY`.
4. `docker compose up -d` en `oracle-vps/` con `MINIPC_TS_IP` puesta en `.env`.
5. Cambiar en Cloudflare los registros A de `pelis` y `fotos-vpn` (nube gris) de la IP de
   Tailscale del mini PC a la IP pública de la VM.

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
- **La trampa de los `$` en `wsl.exe` también aplica llamando desde bash**, no solo desde
  PowerShell 5.1: un `bash -c '...$VAR...'` pasado como argumento a `wsl.exe` pierde las
  variables y el script se ejecuta con ellas vacías, sin dar ningún error. La regla es la
  misma de siempre: escribir el `.sh` y ejecutarlo por su ruta.
- La salida de `wsl.exe` llamado **desde dentro de WSL** viene en UTF-16 con NULs: pasarla por
  `tr -d '\0'` o no se puede grepear.

---

## Estado de `scripts/verificar.sh`

**0 fallos** en la última ejecución conocida en el mini PC (2026-08-28, con los cinco
contenedores en marcha). Entorno WSL, Docker, montajes del NAS y las reglas de almacenamiento
(Postgres en ext4 local), todo en verde.

Se ejecuta **dentro de Ubuntu**, en la máquina real — no vale desde otro sitio:

```bash
bash ~/mediastack/scripts/verificar.sh
```

### Los dos MCP, y por qué uno no se ve desde la nube

- **NAS-MCP** — corre en el NAS y sí se alcanza desde una sesión en la nube. Es el punto de
  observación de la LAN que usa el apartado de abajo. Se cayó y volvió el 2026-09-03; si un día
  no responde, mirar el contenedor `nas-mcp` en `/volume1/docker/nas-mcp`.
- **Un MCP para WSL, local en el mini PC** (Jaime, 2026-09-03). Es **local a propósito**: se usa
  desde el propio mini PC y no se publica hacia fuera.

Y un dato de la misma sesión, que contradice lo que dice la fase 9 más abajo: **Tailscale ya está
instalado y autenticado dentro de Ubuntu.** El 2026-09-03 `hostname -I` en el mini PC devolvía
`100.96.214.61` y una IPv6 `fd7a:115c:a1e0::…`, que es una IP de tailnet asignada. Así que el paso
«ejecutar `wsl/09-tailscale.sh` y autenticar» de la fase 9 **está hecho**, aunque el runbook lo
siga dando por pendiente. Lo que no consta comprobado es el resto de la fase: Caddy, los registros
DNS y la VM de Oracle.

Recordatorio de para qué sirve ahí Tailscale, porque se presta a confusión: es el **túnel privado
entre la VM de Oracle y el mini PC** (`oracle-vps/Caddyfile` → `reverse_proxy {$MINIPC_TS_IP}`).
Va instalado en **un** equipo, el mini PC. Ningún visitante de `pelis.` o `fotos-vpn.` necesita
Tailscale ni instalar nada: entra con el navegador. Eso es justo lo que se decidió el 2026-08-31.

**Que no aparezca desde fuera no es un fallo.** No sale en los conectores de claude.ai, ni en el
NAS, ni en este repo, y así debe ser: una sesión en la nube está fuera de la LAN. Es la misma
decisión que llevó a instalar Claude Code dentro de Ubuntu en vez de abrir un canal remoto — se
descartaron SSH abierto a Internet y un MCP de ejecución de comandos por el túnel (`PASOS.md`
§«Dónde ejecutar cada cosa»). Publicarlo revertiría esa decisión, así que si algún día se plantea,
se habla y se documenta antes, no se da por bueno.

Queda por documentar desde el propio mini PC: nombre, puerto y qué expone.

### Comprobar el estado del mini PC en remoto

Desde una sesión sin acceso a la LAN de casa, el NAS sirve de punto de observación (está en la
misma red). **Ojo con el método**: el contenedor del MCP del NAS corre `dash`, no `bash`, así
que `/dev/tcp/host/puerto` **no existe** ahí y falla siempre en silencio — da «cerrado» para
todo, incluidos los puertos que están abiertos. Un sondeo hecho así el 2026-09-01 llevó a
concluir, mal, que el mini PC estaba apagado.

Lo que sí funciona es `curl`, y siempre **validándolo primero contra el NAS**, que sabemos vivo:

```bash
# ¿responde HTTP?  (000 = no contesta)
for p in 2283 4533 8096; do
  printf '%s -> ' $p
  curl -s -o /dev/null -w '%{http_code}\n' --max-time 8 http://192.168.1.227:$p/
done

# ¿está el equipo encendido?  El código de salida de curl distingue lo que el
# código HTTP no puede. Validar el método contra el NAS antes de creerse nada:
#   192.168.1.205:445  -> 28  (abierto, no habla HTTP)
#   192.168.1.205:9999 -> 7   (cerrado)
curl -s -o /dev/null --connect-timeout 4 --max-time 6 http://192.168.1.227:445/; echo $?
```

| Código de salida | Significa |
|---|---|
| `7` | Conexión rechazada o host inalcanzable |
| `28` | Timeout: puerto filtrado, o el equipo no está |
| `52` / `56` | **Conectó**: hay alguien al otro lado. El equipo está encendido |

### Sondeo del 2026-09-02 (desde el NAS, tras revertir el modo espejo)

Mismo resultado, y esta vez **es el esperado**, no un síntoma:

```
NAS   192.168.1.205:445  -> exit 28   (método validado: abierto, no habla HTTP)
NAS   192.168.1.205:9999 -> exit 7    (método validado: cerrado)
miniPC 192.168.1.227:445  -> exit 56  → encendido y en la red
miniPC 192.168.1.227:2283 -> timeout
miniPC 192.168.1.227:4533 -> timeout
miniPC 192.168.1.227:8096 -> timeout
```

Con el NAT restablecido, que los tres puertos del stack no contesten desde la LAN es lo
correcto: WSL2 solo reenvía a `localhost` de Windows. **Esto no dice nada sobre si los
contenedores están arriba o abajo** — desde fuera no se puede saber. Para eso hay que entrar
al mini PC y correr `verificar.sh`.

### Estado a 2026-09-01: encendido, pero WSL no se ve desde la LAN

`445` da `56` (conecta y corta) → **el mini PC está encendido y en la red**. Pero `2283`, `4533`
y `8096` dan timeout, y un barrido de `192.168.1.0/24` no encuentra esos puertos en **ninguna**
IP: no es que haya cambiado de IP.

La explicación más probable es la de siempre con WSL2: los contenedores escuchan dentro de
Ubuntu, y el reenvío automático de WSL2 solo cubre **`localhost` del propio Windows**. Desde
otro equipo de la LAN no hay nada que responda, aunque el stack esté perfectamente arrancado.
Para confirmarlo, en el mini PC:

```powershell
PS> curl.exe -I http://localhost:2283          # si responde aquí, el stack está bien
PS> netsh interface portproxy show v4tov4      # ¿hay reenvío a la LAN? (esperado: vacío)
PS> Get-NetFirewallRule -DisplayName *2283* | Format-List DisplayName,Enabled,Direction,Action
```

**Esto no bloquea la fase 9**: Tailscale corre *dentro* de Ubuntu y Caddy escucha en la IP del
tailnet, también dentro de Ubuntu, así que todo termina en el mismo sitio que los contenedores
y no necesita exposición a la LAN. Es justo la razón por la que `PLAN.md` §6 puso Tailscale
dentro de WSL y descartó `netsh portproxy`. Lo único que sí rompe es la verificación de la
fase 6 tal como estaba escrita — ya corregida en `PASOS.md` §6.

### Red en modo espejo: probada el 2026-09-02, y la vuelta atrás NO se aplicó hasta el 09-03

Se intentó `networkingMode=mirrored` en `.wslconfig` para que el stack se viera desde la LAN.
**Rompe los montajes NFS del NAS y hubo que volver atrás.**

Lo que funcionó: `hostname -I` dentro de WSL pasó a devolver `192.168.1.227`, la IP de Windows,
que era exactamente el objetivo. Las tres reglas de firewall de Hyper-V se crearon bien
(`wsl/08b-red-mirrored.ps1`).

Lo que rompió: los cuatro montajes del NAS.

```
$ time ls /mnt/nas/musica
ls: cannot open directory '/mnt/nas/musica': No such device
real    0m17.233s
```

`No such device` tras ~17 s es el automount agotando el `timeo=100,retrans=3` sin respuesta del
NFS. El NAS estaba sano: comprobado desde otro equipo de la red, sirve NFS con normalidad. Al
arrancar, WSL ya avisaba con `wsl: Processing /etc/fstab with mount -a failed.`

**Vuelta atrás:** quitar la línea de `.wslconfig` + `wsl --shutdown`. Las reglas de firewall se
dejan puestas: bajo NAT son inertes.

> ⚠️ **Esto se escribió como hecho, y no se hizo.** El 2026-09-03, al abrir sesión en el mini PC,
> `networkingMode=mirrored` seguía en `C:\Users\Admin\.wslconfig` y `hostname -I` devolvía
> `192.168.1.227`. Los cuatro montajes llevaban **~17 horas** dando `No such device` a los 17 s, e
> `immich_server`, `navidrome` y `jellyfin` estaban en estado `created` — creados y nunca
> arrancados, porque sus bind mounts apuntan al NAS. Postgres y Redis aguantaron por vivir en
> ext4 local (`CLAUDE.md` §5).
>
> Dos lecciones, y ninguna es "acuérdate mejor":
> 1. **Decidir una vuelta atrás no es aplicarla.** Se documentó la decisión, no el resultado. Un
>    cambio no está revertido hasta que la máquina lo demuestra.
> 2. **`verificar.sh` lo pintó en ámbar.** Su comprobación de montajes no distinguía "carpeta
>    vacía" de "montaje colgado", así que un fallo duro salía como AVISO y se pudo pasar por alto
>    17 horas. Corregido el 2026-09-03: ahora un montaje que no se puede abrir es FALLO, con el
>    error real. Si hubiera estado así, esto dura minutos.

Y corrige una suposición que estaba escrita en `PLAN.md` §6 y en `wsl/fstab.snippet`: se daba
por hecho que quitar el NAT haría funcionar el locking de NFS y abriría la puerta a `vers=4.1`.
Es al revés. Esa vía queda **descartada**, no pendiente.

**El acceso desde la LAN sigue sin resolver.** Quien lo retome: lo que se juega es el NFS, que
es de lo que come todo el stack. Stack parado, `verificar.sh` antes y después, vuelta atrás
preparada.

