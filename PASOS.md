# PASOS — Runbook de instalación

Pensado para ejecutarse **con Claude Code**, fase a fase. Cada fase tiene:
**objetivo → comandos → resultado esperado → VERIFICACIÓN**.

> **Regla de oro del runbook:** si la verificación de una fase no pasa, **no se avanza**.
> Se arregla o se revierte. Nada de "ya lo miro luego".

> **Regla heredada:** en este runbook no se borra, mueve ni reorganiza nada del NAS.
> Todo lo que toca el NAS es de **solo lectura**, salvo dos carpetas nuevas que se crean
> vacías (`fotos` para las subidas de Immich y `backups/immich-db`).

## Dónde ejecutar cada cosa

| Prefijo | Dónde | Cómo |
|---|---|---|
| `PS>` | PowerShell de Windows **como administrador** | menú inicio → PowerShell → Ejecutar como administrador |
| `$` | Dentro de Ubuntu (WSL) | `wsl -d Ubuntu` o pestaña Ubuntu de Windows Terminal |

**Recomendación:** a partir de la fase 2, instala y lanza **Claude Code dentro de Ubuntu (WSL)**,
no en Windows. Así ve el mismo sistema de ficheros que los contenedores y puede verificar de
verdad lo que está montando.

---

## FASE 0 — Inventario (solo lectura, no cambia nada)

**Objetivo:** saber qué hardware hay y dónde están realmente los ficheros, antes de escribir
una sola línea de configuración. Sin esto, el resto del runbook va a ciegas.

```powershell
PS> Get-CimInstance Win32_Processor | Select-Object Name, NumberOfCores, NumberOfLogicalProcessors
PS> Get-CimInstance Win32_PhysicalMemory | Measure-Object -Property Capacity -Sum | ForEach-Object { "{0:N1} GB" -f ($_.Sum/1GB) }
PS> Get-CimInstance Win32_VideoController | Select-Object Name, DriverVersion
PS> Get-Volume | Where-Object DriveLetter | Select-Object DriveLetter, FileSystemType, @{n='LibreGB';e={[math]::Round($_.SizeRemaining/1GB,1)}}
PS> winver
PS> wsl --status
PS> wsl --list --verbose
```

Y en el NAS (DSM → Panel de control → Carpeta compartida, o por SSH):
carpetas reales de fotos, música y vídeo, y **cuánto ocupan**.

**Rellena esta tabla antes de seguir:**

| Dato | Valor |
|---|---|
| CPU / núcleos | |
| RAM total | |
| iGPU (modelo) | |
| Espacio libre en C: | |
| Windows versión | |
| WSL ya instalado | sí / no |
| Ruta NAS fotos histórico | `/volume1/...` |
| Ruta NAS música | `/volume1/...` |
| Ruta NAS vídeo | `/volume1/...` |
| Tamaño total de fotos | GB |

**VERIFICACIÓN 0:**
- [ ] Hay **≥ 60 GB libres en C:** (WSL + imágenes Docker + Postgres + caché de miniaturas).
      Si no los hay, se para aquí y se libera espacio o se mueve el `.vhdx` de WSL a otro disco.
- [ ] La CPU es x86-64-v2 o superior (cualquier Intel/AMD de 2012 en adelante). Immich v3 lo exige.
- [ ] Están anotadas las rutas reales del NAS.

---

## FASE 1 — WSL2 + Ubuntu

Lo hacen los dos scripts del repo, en este orden (PowerShell **como administrador**):

```powershell
PS> cd C:\claude\mediastack\wsl
PS> powershell -ExecutionPolicy Bypass -File .\01-instalar-wsl2.ps1   # activa componentes, pide REINICIO
# ... reiniciar ...
PS> powershell -ExecutionPolicy Bypass -File .\01-instalar-wsl2.ps1   # segunda pasada: instala Ubuntu y escribe .wslconfig
PS> wsl -d Ubuntu-24.04                                              # crea el usuario normal (NO root)
PS> powershell -ExecutionPolicy Bypass -File .\02-configurar-ubuntu.ps1
```

Detalles que cuestan una tarde si no se saben:

- El componente `Microsoft-Windows-Subsystem-Linux` **se queda en `Disabled` para siempre**
  y no pasa nada: solo hace falta para WSL1. El que decide es `VirtualMachinePlatform`.
- Ubuntu se instala con `--no-launch`, así que **arranca como root** hasta que
  `/etc/wsl.conf` fija `[user] default=`. Si la cuenta ya existe (`adduser` + `usermod -aG
  sudo`), el paso `wsl -d Ubuntu-24.04` de arriba sobra.
- El `.wslconfig` lo genera el script 01 en `C:\Users\<TU_USUARIO>\.wslconfig` ajustado a la
  RAM y los núcleos reales; `wsl/.wslconfig.example` queda solo como referencia.
- El script 02 copia `wsl/wsl.conf` a `/etc/wsl.conf` dentro de Ubuntu y hace `wsl --shutdown`.
  Lo pasa por un `.sh` temporal a propósito: `wsl.exe` se come los `$` y las `\` de lo que
  le llega por la línea de comandos, y PowerShell 5.1 mete un BOM si se usa la entrada estándar.

**VERIFICACIÓN 1** (volver a entrar en Ubuntu):

```bash
$ wsl.exe --list --verbose      # Ubuntu-24.04 · Running · 2
$ systemctl is-system-running   # running  (o degraded: aceptable en WSL)
$ free -h                       # el total debe rondar los 5 GB del .wslconfig
$ nproc
```

- [ ] La versión es **2**, no 1.
- [ ] `systemd` responde (si dice "command not found", `/etc/wsl.conf` no se aplicó).
- [ ] `free -h` refleja el límite del `.wslconfig` (~5 GB). Si muestra los 7,9 GB del equipo,
      el fichero no está donde debe o falta `wsl --shutdown`.

---

## FASE 2 — Docker Engine dentro de WSL

**No instalar Docker Desktop.** Motivos en `PLAN.md` §2.

```bash
$ sudo apt update && sudo apt upgrade -y
$ curl -fsSL https://get.docker.com | sudo sh
$ sudo usermod -aG docker $USER
$ sudo systemctl enable --now docker
# cerrar y reabrir la sesión de WSL para que el grupo docker haga efecto
```

**VERIFICACIÓN 2:**

```bash
$ docker run --rm hello-world
$ docker compose version         # v2.x — "docker-compose" v1 NO sirve
$ systemctl is-enabled docker    # enabled
$ docker info --format '{{.Driver}}'       # overlayfs (en Docker <29 se llamaba overlay2)
```

- [ ] `hello-world` sale sin `sudo`.
- [ ] `docker compose version` (con espacio) responde v2 o superior.
- [ ] `docker` está `enabled`, si no, no arrancará solo.

---

## FASE 3 — Montajes del NAS

### En el NAS (DSM), primero:

1. Panel de control → **Servicios de archivos → NFS** → *Habilitar NFS*, versión máxima **NFSv4.1**.
2. En cada carpeta compartida (fotos, música, vídeo) → Editar → **Permisos NFS** → Crear:
   - Nombre de host / IP: **la IP del mini PC**
   - Privilegio: **Solo lectura** para música, vídeo e histórico de fotos; **Lectura/Escritura**
     solo para la carpeta nueva de subidas de Immich.
   - Squash: *Asignar todos los usuarios a admin* (lo más simple) o mapear a un usuario propio.
   - Marcar *Permitir conexiones desde puertos no privilegiados* y *Permitir acceso a
     subcarpetas montadas*.
3. Crear la carpeta nueva `foto/immich-subidas` (o la que decidas) para las subidas del móvil.
   **No se mueve ni se reorganiza nada existente.**

### En WSL:

```bash
$ sudo apt install -y nfs-common
$ sudo mkdir -p /mnt/nas/{fotos,fotos-historico,musica,video,backups}
# probar A MANO antes de tocar /etc/fstab:
$ sudo mount -t nfs -o vers=4.1,soft,timeo=150 192.168.1.205:/volume1/foto /mnt/nas/fotos-historico
$ ls /mnt/nas/fotos-historico | head
```

Si el `ls` muestra las fotos: desmontar, meter las líneas de `wsl/fstab.snippet` en `/etc/fstab`
con las rutas reales, y `sudo systemctl daemon-reload && sudo mount -a`.

Si NFS da problemas de permisos (típico con Synology): usar la **variante B (CIFS)** del mismo
fichero. Funciona, pero rinde peor con muchos ficheros pequeños.

**VERIFICACIÓN 3:**

```bash
$ mount | grep /mnt/nas
$ ls -la /mnt/nas/fotos-historico | head
$ df -h /mnt/nas/*
$ touch /mnt/nas/fotos/PRUEBA_ESCRITURA && rm /mnt/nas/fotos/PRUEBA_ESCRITURA && echo "escritura OK"
$ touch /mnt/nas/musica/NO_DEBERIA 2>&1 | grep -q "read-only" && echo "música es read-only, correcto"
```

- [ ] Los cuatro montajes aparecen en `mount`.
- [ ] Se **leen** ficheros reales del histórico.
- [ ] Se **escribe** en la carpeta de subidas de Immich.
- [ ] **NO** se puede escribir en música, vídeo ni histórico.
- [ ] Tras `wsl --shutdown` y volver a entrar, los montajes vuelven solos
      (esto es lo que valida el `x-systemd.automount`).

---

## FASE 4 — Repo en GitHub

Todo el stack vive en git, y **se edita en git y se hace pull en el mini PC** — misma regla
que en el NAS. Nunca al revés.

```bash
$ cd ~ && git clone git@github.com:<tu-usuario>/mediastack.git
# o: crear el repo con gh y volcar los ficheros de este paquete
$ cd ~/mediastack && ls
```

**VERIFICACIÓN 4:**

```bash
$ git -C ~/mediastack status --short   # limpio
$ cat ~/mediastack/.gitignore | grep -E '^\.env|^\*\*/\.env'
```

- [ ] `.env` y `*.env` están en `.gitignore`. **Ningún secreto entra en el repo.**
- [ ] `CLAUDE.md` está en la raíz (reglas de seguridad para las sesiones de Claude Code).

---

## FASE 5 — Immich

```bash
$ mkdir -p /var/lib/mediastack/immich/postgres
$ sudo chown -R $USER:$USER /var/lib/mediastack
$ cd ~/mediastack/immich

# El compose OFICIAL se descarga, no se escribe a mano ni se edita nunca:
$ wget -O docker-compose.yml https://github.com/immich-app/immich/releases/latest/download/docker-compose.yml
$ wget -O hwaccel.transcoding.yml https://github.com/immich-app/immich/releases/latest/download/hwaccel.transcoding.yml
$ wget -O hwaccel.ml.yml https://github.com/immich-app/immich/releases/latest/download/hwaccel.ml.yml

$ cp .env.example .env
$ sed -i "s/^DB_PASSWORD=.*/DB_PASSWORD=$(openssl rand -hex 24)/" .env
$ nano .env      # ajustar UPLOAD_LOCATION y EXTERNAL_LIBRARY a las rutas reales

# ANTES de arrancar: ver la configuración ya fusionada con el override
$ docker compose config | grep -A3 -E 'volumes|DB_DATA_LOCATION'
$ docker compose up -d
$ docker compose logs -f immich-server     # Ctrl+C cuando diga que escucha en 2283
```

> **Sin machine learning.** El override le pone el perfil `ml` al contenedor de machine
> learning, así que `docker compose up -d` levanta **tres** servicios, no cuatro. Es
> deliberado: con 7,9 GB de RAM no cabe en horario normal (ver `PLAN.md` §3 y el anexo ML
> al final de este documento).

Después, en `http://192.168.1.227:2283`:

1. Crear el usuario administrador (el primero que entra es admin).
2. Administración → Ajustes → **Machine Learning** → *desactivar*. Si se queda activo con el
   contenedor apagado, los trabajos fallan y se reintentan sin parar.
3. Administración → **Bibliotecas externas** → nueva biblioteca → ruta `/mnt/nas/fotos-historico`
   → *Escanear*.
4. Administración → Ajustes → Trabajos: bajar la concurrencia a **1** en generación de
   miniaturas y extracción de metadatos. En un N150 con 4 hilos, subirla no acelera: satura.
5. Dejar el escaneo inicial corriendo **de noche**.

**VERIFICACIÓN 5:**

```bash
$ docker compose ps                                    # 4 servicios Up (healthy)
$ docker exec immich_postgres df -h /var/lib/postgresql/data | tail -1
$ docker compose config | grep DB_DATA_LOCATION -A2
$ curl -s http://localhost:2283/api/server/ping         # {"res":"pong"}
$ bash ~/mediastack/scripts/verificar.sh
```

- [ ] Los **3** contenedores (`server`, `postgres`, `redis`) están `healthy`, y
      `machine_learning` **no** aparece: es lo esperado.
- [ ] **Postgres NO está en `/mnt/`.** Este es el chequeo más importante de todo el runbook.
- [ ] El histórico aparece en la línea de tiempo tras el primer escaneo.
- [ ] Subir una foto de prueba desde la web → aparece un fichero nuevo **en el NAS**, dentro de
      `UPLOAD_LOCATION`, y **nada** se ha escrito en el histórico.
- [ ] La app móvil de Immich conecta por IP local y hace la copia de seguridad.

---

## FASE 6 — Arranque automático tras un corte de luz

WSL **no arranca solo** al encender Windows. Sin esto, un corte de luz deja los tres servicios
caídos hasta que alguien inicie sesión en el mini PC.

Tres piezas, las tres necesarias:

1. **Windows arranca solo al volver la luz** → BIOS/UEFI → *Restore on AC Power Loss = Power On*.
2. **Inicio de sesión automático** (el mini PC no tiene a nadie delante) → `netplwiz` →
   desmarcar "Los usuarios deben escribir su nombre...". *Ojo: implica que quien encienda el
   equipo entra sin contraseña. Si el mini PC está en un sitio no controlado, no lo hagas y usa
   en su lugar una tarea con "Ejecutar tanto si el usuario inició sesión como si no".*
3. **Tarea programada que levanta WSL y el stack:**

```powershell
PS> $accion  = New-ScheduledTaskAction -Execute "C:\Windows\System32\wsl.exe" `
      -Argument '-d Ubuntu-24.04 -u root -- bash -lc "sudo -u TU_USUARIO /home/TU_USUARIO/mediastack/scripts/arrancar-stack.sh >> /var/log/mediastack-boot.log 2>&1"'
PS> $disparador = New-ScheduledTaskTrigger -AtStartup
PS> $opciones = New-ScheduledTaskSettingsSet -AllowStartIfOnBatteries -DontStopIfGoingOnBatteries -StartWhenAvailable -ExecutionTimeLimit 0
PS> Register-ScheduledTask -TaskName "MediaStack" -Action $accion -Trigger $disparador -Settings $opciones -RunLevel Highest -User "SYSTEM"
```

**VERIFICACIÓN 6 — la prueba de verdad:**

```powershell
PS> Restart-Computer
```

Esperar 5 minutos **sin tocar el teclado ni iniciar sesión a mano**, y desde otro equipo:

```bash
$ curl -I http://<ip-del-minipc>:2283
```

- [ ] Immich responde tras un reinicio en frío sin intervención humana.
- [ ] `wsl -d Ubuntu-24.04 -- cat /var/log/mediastack-boot.log` muestra el arranque.
- [ ] Los montajes del NAS están puestos tras el reinicio.

---

## FASE 7 — Navidrome, Jellyfin y backup

```bash
$ mkdir -p /var/lib/mediastack/{navidrome/data,jellyfin/{config,cache}}

$ cd ~/mediastack/navidrome && echo "PUID=$(id -u)"$'\n'"PGID=$(id -g)" > .env && docker compose up -d
$ cd ~/mediastack/jellyfin  && echo "PUID=$(id -u)"$'\n'"PGID=$(id -g)"$'\n'"TZ=Europe/Madrid" > .env && docker compose up -d

# backup diario de la BBDD de Immich (las fotos ya las respalda el NAS; los álbumes NO)
$ mkdir -p /mnt/nas/backups/immich-db
$ crontab -e
#   30 0 * * * /home/TU_USUARIO/mediastack/scripts/backup-immich-db.sh >> /var/log/immich-backup.log 2>&1
```

Jellyfin (`http://<ip>:8096`): asistente inicial, y añadir bibliotecas apuntando a `/media/...`
(la ruta **dentro del contenedor**, no la de WSL).

**VERIFICACIÓN 7:**

```bash
$ curl -s http://localhost:4533/ping
$ curl -s http://localhost:8096/health
$ docker logs navidrome 2>&1 | grep -iE "scan|error" | tail -20
$ bash ~/mediastack/scripts/backup-immich-db.sh && ls -lh /mnt/nas/backups/immich-db/
$ bash ~/mediastack/scripts/verificar.sh    # debe salir 0 fallos
```

- [ ] Navidrome ve el número correcto de canciones (comparar con el conteo del NAS).
- [ ] Jellyfin reproduce un vídeo en el navegador **sin transcodificar** (Panel → Reproducciones
      activas debe decir *Direct Play*; si dice *Transcoding* en CPU, ahí se va la RAM).
- [ ] El volcado de Postgres existe en el NAS y **pesa más de 0 bytes**.
- [ ] Con todo levantado, `free -h` deja **≥ 1 GB libre** en WSL (de los 5 asignados).
      Si no, algo se está pasando de su `mem_limit`: mirar `docker stats`.
- [ ] En Windows, el Administrador de tareas deja **≥ 1 GB libre** con el stack en marcha.

---

## FASE 8 — Opcional: iGPU y miniaturas rápidas

Solo con todo lo anterior verificado y estable **una semana**.

**8a. iGPU en Immich** (config oficial para WSL2):
descomentar el bloque `vaapi-wsl` / `openvino-wsl` de `immich/docker-compose.override.yml`,
`docker compose up -d`, y comprobar con `docker exec immich_server ffmpeg -hwaccels` que
aparece `vaapi`. Si el transcode falla → volver a comentar. Sin dramas.

**8b. iGPU en Jellyfin** (no oficial en WSL, experimental):
`cp jellyfin/docker-compose.hwaccel-wsl.yml.example jellyfin/docker-compose.override.yml`.

**8c. Miniaturas de Immich en SSD local** (no documentado oficialmente, hazlo consciente):
mover `thumbs/` y `encoded-video/` fuera del NAS acelera mucho la línea de tiempo, pero
son datos regenerables que dejan de estar cubiertos por el backup del NAS. Solo si la
navegación va lenta de verdad.

---

## FASE 9 — Acceso desde fuera

**Nombres definitivos y cómo se publica cada uno:**

| Hostname | Servicio | Cloudflare |
|---|---|---|
| `fotos.ruizespana.com` | Immich :2283 | Túnel, **proxy naranja** |
| `musica.ruizespana.com` | Navidrome :4533 | Túnel, **proxy naranja** |
| `pelis.ruizespana.com` | Jellyfin :8096 | Registro A **solo DNS (gris)** → IP Tailscale |
| `fotos-vpn.ruizespana.com` | Immich :2283 | Registro A **solo DNS (gris)** → IP Tailscale |
| `casa.ruizespana.com` | Homepage :3000 | Registro A **solo DNS (gris)** → IP Tailscale |

Los tres últimos no llegan al servicio directamente: pasan por **Caddy** (`caddy/`), que
escucha solo en la IP del tailnet y da HTTPS con certificado válido. Sin Caddy tendrías que
escribir el puerto a mano (`pelis.ruizespana.com:8096`) y sin cifrar. Ver `PLAN.md` §6.

### 9.1 — Tailscale, dentro de WSL

```bash
$ wsl -d Ubuntu-24.04 -u root -- /home/jaime/mediastack/wsl/09-tailscale.sh
# el script deja tailscaled instalado y activo; luego, autenticar:
$ sudo tailscale up --hostname=minipc-jrh     # imprime una URL: abrirla en el navegador
$ tailscale ip -4                             # → 100.x.y.z, la IP que va en todo lo demás
```

### 9.2 — Registros DNS grises

En la zona `ruizespana.com`, tres registros **A** en modo **solo DNS (nube GRIS)** apuntando a
esa `100.x.y.z`: `pelis`, `fotos-vpn` y `casa`. En naranja no funcionarían: Cloudflare no
puede alcanzar una IP del rango 100.64.0.0/10.

### 9.3 — Token de Cloudflare para los certificados

Cloudflare → My Profile → API Tokens → *Create Token* → plantilla **Edit zone DNS**, acotada a
la zona `ruizespana.com` (permiso `Zone:DNS:Edit`). Es lo único que Caddy necesita para el
reto DNS-01; no publica nada.

```bash
$ cd ~/mediastack/caddy && cp .env.example .env && chmod 600 .env
# rellenar TS_IP, CF_API_TOKEN y ACME_EMAIL
```

### 9.4 — Levantar Caddy y el portal

```bash
$ sudo mkdir -p /var/lib/mediastack/caddy/{data,config}
$ sudo chown -R 1000:1000 /var/lib/mediastack/caddy

$ cd ~/mediastack/homepage && cp .env.example .env && chmod 600 .env && docker compose up -d
$ cd ~/mediastack/caddy && docker compose up -d --build   # la primera vez compila Caddy
$ docker compose logs -f caddy                            # ver la emisión de certificados
```

### 9.5 — El túnel, para lo que sí va por Cloudflare

`cloudflared/docker-compose.yml` está listo. Leer sus avisos de cabecera y `PLAN.md` §6 antes.
En el panel del túnel **MiniPC_Jaime** deben quedar solo `fotos` y `musica`: si sigue estando
`pelis.ruizespana.com`, **borrarla** — ese es justo el tráfico que no queremos por el proxy.

**VERIFICACIÓN 9:**

```bash
$ tailscale status | head                       # el mini PC aparece como minipc-jrh
$ curl -sI https://pelis.ruizespana.com | head -1   # desde otro equipo DEL tailnet
```

- [ ] `https://casa.ruizespana.com` abre el portal, con **candado válido** (no aviso de
      certificado): eso demuestra que el DNS-01 funcionó.
- [ ] `https://pelis.ruizespana.com` abre Jellyfin **sin puerto en la URL**.
- [ ] Desde un equipo **fuera del tailnet**, esos tres nombres **no responden**. Si responden,
      Caddy no está atado a `TS_IP` y los servicios están expuestos: pararlo y revisar.
- [ ] Desde datos móviles (**Wi-Fi apagado**), con Tailscale activo en el móvil: la app de
      Immich apuntando a `https://fotos-vpn.ruizespana.com` sube una **foto**.
- [ ] Y sube un **vídeo de más de 100 MB**. Por Tailscale debe funcionar; por el túnel
      **fallaría** — es el comportamiento esperado, no un bug tuyo.
- [ ] En el panel del túnel ya **no** está `pelis.ruizespana.com`.
- [ ] El túnel del NAS (n8n, flota, erp, mcp) sigue funcionando igual: **no se ha tocado**.

---

## Anexo ML — Caras y búsqueda por contenido, a ratos

Con 7,9 GB de RAM, el machine learning de Immich no cabe en horario normal. La estrategia es
**digerir el histórico por tandas nocturnas** y luego decidir si compensa dejarlo encendido.

**Una tanda:**

```bash
$ bash ~/mediastack/scripts/ml.sh on
# web → Administración → Ajustes → Machine Learning → ACTIVAR
# web → Administración → Trabajos → lanzar "Búsqueda inteligente" y
#       "Reconocimiento facial", concurrencia 1
$ watch -n 30 'docker stats --no-stream --format "{{.Name}} {{.MemUsage}}"'
```

**Al terminar (o por la mañana):**

```bash
# web → Ajustes → Machine Learning → DESACTIVAR   (primero esto, siempre)
$ bash ~/mediastack/scripts/ml.sh off
```

**Qué vigilar durante la tanda:**

- `immich_machine_learning` no debe pasar de los 2,5 GB de su `mem_limit`. Si Docker lo mata
  por OOM, se reinicia solo y el trabajo continúa: no es un desastre, pero significa que hay
  que bajar la concurrencia a 1 si no lo estaba.
- Si Postgres o el servidor se reinician durante la tanda, para el ML y déjalo para cuando el
  PC no tenga nada más abierto.
- La primera pasada sobre una biblioteca grande son **horas**, no minutos. Es normal en un N150.

**Cuándo dejar de hacer tandas:** cuando la cola de trabajos quede vacía. A partir de ahí, las
fotos nuevas del día son un puñado y se pueden procesar en una tanda corta al mes. Si te
resulta engorroso, esa es la señal de que toca plantearse Ubuntu Server puro en este equipo
(`PLAN.md` §3).

---

## Anexo — Mantenimiento

```bash
# actualizar una app (Immich publica cambios de esquema: leer las release notes antes)
$ cd ~/mediastack/immich && docker compose pull && docker compose up -d

# ver qué se está comiendo la RAM
$ docker stats --no-stream

# revisión completa
$ bash ~/mediastack/scripts/verificar.sh
```

Antes de cada actualización de Immich: **volcado de la BBDD a mano** con
`scripts/backup-immich-db.sh`. Es un minuto y evita un disgusto.
