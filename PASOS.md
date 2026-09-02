# PASOS — Runbook de instalación

Pensado para ejecutarse **con Claude Code**, fase a fase. Cada fase tiene:
**objetivo → comandos → resultado esperado → VERIFICACIÓN**.

> **Regla de oro del runbook:** si la verificación de una fase no pasa, **no se avanza**.
> Se arregla o se revierte. Nada de "ya lo miro luego".

> **Regla heredada:** en este runbook no se borra, mueve ni reorganiza nada del NAS.
> De los cuatro montajes, tres son de **solo lectura** (`photo`, `music`, `video`). El único
> con escritura es `Media`, y ahí se escribe únicamente en lo que Immich sube y en la
> subcarpeta `backup-immich`, que crea sola `scripts/backup-immich-db.sh`.

## Dónde ejecutar cada cosa

| Prefijo | Dónde | Cómo |
|---|---|---|
| `PS>` | PowerShell de Windows **como administrador** | menú inicio → PowerShell → Ejecutar como administrador |
| `$` | Dentro de Ubuntu (WSL) | `wsl -d Ubuntu` o pestaña Ubuntu de Windows Terminal |

**Recomendación:** a partir de la fase 2, instala y lanza **Claude Code dentro de Ubuntu (WSL)**,
no en Windows. Así ve el mismo sistema de ficheros que los contenedores y puede verificar de
verdad lo que está montando.

### Instalar Claude Code dentro de Ubuntu

Decidido el 2026-09-01, después de comprobar que una sesión en la nube no alcanza este equipo:
no está en la LAN de casa y no conserva nada entre sesiones. Las alternativas para dárselo —
SSH abierto a Internet, o un MCP de ejecución de comandos publicado por el túnel — son mucha
superficie nueva en la máquina donde están las fotos de la familia. Trabajar desde dentro no
cuesta nada de eso.

```bash
$ curl -fsSL https://claude.ai/install.sh | bash   # instalador nativo, sirve para WSL
$ exec $SHELL -l                                   # para que ~/.local/bin entre en el PATH
$ claude --version
$ cd ~/mediastack && claude                        # la primera vez pide iniciar sesión
```

No hace falta `sudo`: instala en `~/.local/bin`. Viene bien, porque en este equipo `jaime` se
creó con `--disabled-password` y `sudo` desde dentro pide una contraseña que no existe
(`HANDOFF.md` lo explica y da la vuelta por `wsl.exe -u root`).

El login abre una URL: desde WSL se abre en el navegador de Windows por el interop.

Al arrancar en `~/mediastack`, Claude Code lee el `CLAUDE.md` del repo y hereda sus reglas
duras. Desde el 2026-09-01 **esta copia es la que commitea y empuja** (regla 2), y
`C:\claude\mediastack` queda congelada hasta que Jaime la borre al terminar la instalación.
No hay que sincronizar nada a mano entre las dos: la de Windows ya no se toca.

Excepción por pura cronología: `wsl/00-inventario.ps1`, `01-instalar-wsl2.ps1` y
`02-configurar-ubuntu.ps1` se ejecutan **antes de que Ubuntu exista**, así que sus cabeceras
siguen apuntando a una ruta de Windows. Solo hacen falta para reconstruir el equipo desde cero,
y en ese caso lo que hay es un clon nuevo, no esta copia congelada.

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

```powershell
PS> wsl --install -d Ubuntu-24.04
# reiniciar si lo pide, y crear usuario + contraseña de Ubuntu cuando arranque
PS> wsl --set-default-version 2
PS> wsl --update
```

Copiar `wsl/.wslconfig.example` a `C:\Users\<TU_USUARIO>\.wslconfig` y **ajustar
`processors` al número de núcleos** de la fase 0.

Copiar `wsl/wsl.conf` a `/etc/wsl.conf` dentro de Ubuntu:

```bash
$ sudo cp /ruta/al/repo/wsl/wsl.conf /etc/wsl.conf
```

```powershell
PS> wsl --shutdown
```

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
$ docker info | grep -i "storage driver"   # overlay2
```

- [ ] `hello-world` sale sin `sudo`.
- [ ] `docker compose version` (con espacio) responde v2.
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

Después, en el navegador **del propio mini PC**, en `http://localhost:2283` (desde otro equipo
de la LAN no responde: ver el aviso de la fase 6):

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
2. **La tarea programada** (abajo). No hace falta inicio de sesión automático: la tarea corre
   *tanto si el usuario inició sesión como si no*.
3. **Que el NAS arranque antes que el mini PC**, o al menos que no tarde más. Si el mini PC
   gana la carrera, `arrancar-stack.sh` espera hasta 5 minutos a que aparezcan los montajes.

### ⚠️ La tarea NO puede correr como SYSTEM

Es el error del recipe "de manual" y falla **en silencio**. Las distribuciones de WSL se
registran **por usuario de Windows**, en `HKCU\Software\Microsoft\Windows\CurrentVersion\Lxss`.
Comprobado en este equipo el 2026-08-28: `Ubuntu-24.04` cuelga del perfil de `Admin`, y la rama
`Lxss` de `S-1-5-18` (SYSTEM) está **vacía**. Una tarea como SYSTEM lanzaría `wsl.exe` sin
encontrar ninguna distribución.

La tarea corre como **el usuario dueño de la distro**, con `LogonType S4U`: se ejecuta sin
sesión iniciada y **sin guardar la contraseña**. S4U no da credenciales de red de Windows, cosa
que aquí da igual porque los montajes del NAS los hace Linux dentro de WSL.

```powershell
PS> powershell -ExecutionPolicy Bypass -File \\wsl.localhost\Ubuntu-24.04\home\jaime\mediastack\wsl\06-arranque-automatico.ps1
```

El script comprueba la elevación y que la distro pertenezca a ese usuario antes de registrar
nada, y es idempotente. Ya se ejecutó el 2026-08-28; esto queda por si hay que rehacerlo.

La tarea que registra ejecuta `C:\Windows\System32\wsl.exe` con una ruta **de dentro de
WSL**, no del repo de Windows. Por eso borrar `C:\claude\mediastack` (CLAUDE.md §2) no rompe
el arranque automático.

### Qué levanta

`scripts/boot-mediastack.sh` (como root) → espera a `dockerd` → baja a `jaime` →
`scripts/arrancar-stack.sh` → espera a los montajes del NAS → `docker compose up -d` de los
tres stacks. Log en `/var/log/mediastack-boot.log`.

**VERIFICACIÓN 6:**

Primero, sin reiniciar:

```powershell
PS> Start-ScheduledTask -TaskName MediaStack
PS> Get-ScheduledTaskInfo -TaskName MediaStack | Format-List LastRunTime, LastTaskResult
PS> wsl -d Ubuntu-24.04 -- tail -40 /var/log/mediastack-boot.log
```

Códigos que vas a ver:

| Código | Significa |
|---|---|
| `0` | Terminó bien |
| `267009` | Se está ejecutando ahora mismo — vuelve a mirar en un minuto |
| `267011` | Nunca se ha llegado a ejecutar |
| `267014` | Alguien la paró a mano |

Y luego la prueba de verdad:

```powershell
PS> Restart-Computer
```

Esperar 5 minutos **sin tocar el teclado ni iniciar sesión a mano**.

> ⚠️ **`curl -I http://192.168.1.227:2283` desde otro equipo NO vale como prueba**, aunque sea
> lo que pedía este runbook hasta el 2026-09-01. Los contenedores escuchan dentro de Ubuntu y
> el reenvío automático de WSL2 solo cubre `localhost` **del propio Windows**: desde la LAN no
> responde nadie ni con el stack perfectamente arrancado. Comprobado el 2026-09-01 sondeando
> desde el NAS — ningún equipo del `192.168.1.0/24` sirve 2283/4533/8096, con el mini PC
> encendido. Que falle eso no dice nada sobre el arranque automático.
>
> **Salvo que ya hayas hecho la fase 8b** (red en modo espejo): a partir de ahí sí responde
> desde la LAN, y entonces `curl -I http://192.168.1.227:2283` desde otro equipo vuelve a ser
> la prueba buena, la más limpia de todas.

Pasados los cinco minutos, ya puedes iniciar sesión: lo que se comprueba es que el stack
llevaba rato en pie **antes** de que tú tocaras nada, y para eso valen las marcas de tiempo.

```powershell
PS> Get-CimInstance Win32_OperatingSystem | Select-Object LastBootUpTime
PS> wsl -d Ubuntu-24.04 -- docker ps --format '{{.Names}}\t{{.Status}}'
PS> wsl -d Ubuntu-24.04 -- tail -40 /var/log/mediastack-boot.log
```

- [ ] El `Status` de los contenedores dice `Up N minutes`, coherente con `LastBootUpTime` y
      **anterior** al momento en que iniciaste sesión. Eso es lo que prueba que arrancó solo.
- [ ] `/var/log/mediastack-boot.log` muestra el arranque, con la marca de tiempo del reinicio.
- [ ] Los montajes del NAS están puestos tras el reinicio (`mount | grep 192.168.1.205`).
- [ ] `bash ~/mediastack/scripts/verificar.sh` sale con 0 fallos.

Y la prueba **desde otro equipo**, la que de verdad convence, queda disponible en cuanto esté
la fase 9b (Tailscale): desde cualquier dispositivo del tailnet,

```bash
$ curl -I http://100.x.y.z:2283      # la IP de 'tailscale ip -4' en el mini PC
```

Eso sí funciona sin exponer nada a la LAN, porque `tailscaled` corre **dentro** de Ubuntu, en
el mismo sitio que los contenedores (`PLAN.md` §6).

---

## FASE 7 — Navidrome, Jellyfin y backup

```bash
$ mkdir -p /var/lib/mediastack/{navidrome/data,jellyfin/{config,cache}}

$ cd ~/mediastack/navidrome && echo "PUID=$(id -u)"$'\n'"PGID=$(id -g)"$'\n'"TZ=Europe/Madrid" > .env && docker compose up -d
$ cd ~/mediastack/jellyfin  && echo "PUID=$(id -u)"$'\n'"PGID=$(id -g)"$'\n'"TZ=Europe/Madrid" > .env && docker compose up -d

# backup diario de la BBDD de Immich (las fotos ya las respalda el NAS; los álbumes NO)
$ crontab -e
#   30 0 * * * /home/jaime/mediastack/scripts/backup-immich-db.sh >> /home/jaime/immich-backup.log 2>&1
```

**No hay que crear ninguna carpeta en el NAS a mano.** Los volcados van a
`/mnt/nas/fotos/backup-immich` — una subcarpeta del recurso `Media` que Immich ya usa como
`UPLOAD_LOCATION`, decisión de Jaime del 2026-08-27 para no añadir una carpeta compartida
nueva. `scripts/backup-immich-db.sh` la crea él solo, comprueba antes que `/mnt/nas/fotos` esté
montado, y rota los volcados de más de 30 días **dentro de esa carpeta y de ninguna otra**.

Jellyfin (`http://localhost:8096`, en el navegador del propio mini PC — desde otro equipo de la
LAN no responde, ver el aviso de la fase 6): asistente inicial, y añadir bibliotecas apuntando a
`/media/...` (la ruta **dentro del contenedor**, no la de WSL). Si pones `/mnt/nas/video`,
Jellyfin no encuentra nada y parece que el montaje está roto.

Navidrome (`http://localhost:4533`): crear el usuario. El primero que entra es el administrador.

**VERIFICACIÓN 7:**

```bash
$ curl -s http://localhost:4533/ping
$ curl -s http://localhost:8096/health
$ docker logs navidrome 2>&1 | grep -iE "scan|error" | tail -20
$ bash ~/mediastack/scripts/backup-immich-db.sh && ls -lh /mnt/nas/fotos/backup-immich/
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

**8c. Miniaturas de Immich en SSD local: descartado en este equipo.** Acelera la línea de
tiempo, pero el SSD es de 128 GB y las miniaturas son un 10-20% de la biblioteca. El espacio
manda sobre la velocidad: se quedan en el NAS.

---

## FASE 8b — Ver los servicios desde la LAN (red en modo espejo)

> # ❌ PROBADO EL 2026-09-02: NO FUNCIONA EN ESTE EQUIPO
>
> **El modo espejo rompe los montajes NFS del NAS.** No lo apliques. El procedimiento se deja
> escrito abajo porque está bien y puede servir en otra máquina, pero aquí terminó en vuelta
> atrás. Lo que pasó, con detalle, en «Resultado» justo debajo.

**Decisión de Jaime, 2026-09-01.** Hasta aquí los contenedores solo respondían en `localhost`
del propio Windows: WSL2 sale por NAT y su reenvío automático no cubre la red local, así que
desde el portátil o la tele de casa no contestaba nadie en `192.168.1.227`. Se intentó
resolver poniendo la red de WSL en **modo espejo**, no con `netsh portproxy` (descartado en
`PLAN.md` §6 por frágil: la IP de WSL cambia en cada arranque).

### Resultado del intento — 2026-09-02

El modo espejo **sí hizo su trabajo**: `hostname -I` dentro de WSL pasó a devolver
`192.168.1.227`, la IP de Windows, que es exactamente lo que se buscaba. Las tres reglas de
firewall se crearon sin problema.

**Pero los cuatro montajes del NAS dejaron de funcionar.** El síntoma exacto:

```
$ time ls /mnt/nas/musica
ls: cannot open directory '/mnt/nas/musica': No such device
real    0m17.233s
```

`No such device` tras ~17 segundos es la firma del automount fallando: systemd intenta montar,
el NFS no responde dentro del `timeo=100,retrans=3` de `wsl/fstab.snippet`, y el automount
devuelve ENODEV. Los cuatro montajes igual. Antes del cambio, `verificar.sh` daba «montado y
con contenido legible» en los cuatro; después, AVISO en los cuatro. Ya al arrancar WSL avisaba:
`wsl: Processing /etc/fstab with mount -a failed.`

No es del NAS: se comprobó desde otro equipo de la red que sirve NFS con normalidad (el 2049
acepta conexiones). Es el cliente, dentro de WSL, en modo espejo.

⚠️ **Y falsifica lo que este mismo runbook daba por hecho.** Se escribió que el modo espejo
haría *desaparecer* la limitación que obliga a montar con `vers=3,nolock` — el NAT impedía que
el NAS llamara de vuelta al cliente. La realidad es la contraria: sin NAT, el montaje ni
siquiera se completa. La idea de pasar a `vers=4.1` con bloqueo por esta vía queda descartada.

**Decisión: vuelta atrás.** Quitar `networkingMode=mirrored` de `.wslconfig` y `wsl --shutdown`.
Las reglas de firewall de Hyper-V se dejan puestas: bajo NAT son inertes y no estorban.

El acceso desde la LAN **queda sin resolver**, y con las tres opciones de `PLAN.md` §6 en pie
menos ésta. Antes de reintentarlo por otra vía, tener presente que lo que se juega es el NFS,
que es de lo que come todo el stack.

---

### Procedimiento (se deja documentado; NO aplicar en este equipo)

> ⚠️ Esto cambia la red de WSL entera. Se hace **con el stack parado** y se verifican los
> montajes del NAS después, porque son lo que más se puede resentir. En este equipo es
> justamente donde falló.

### 1. Parar el stack

```bash
$ cd ~/mediastack/immich    && docker compose down
$ cd ~/mediastack/navidrome && docker compose down
$ cd ~/mediastack/jellyfin  && docker compose down
```

### 2. Modo espejo en `.wslconfig`

En Windows, añadir a `C:\Users\Admin\.wslconfig`, dentro de `[wsl2]` (está ya en
`wsl/.wslconfig.example`, con el porqué):

```ini
networkingMode=mirrored
```

```powershell
PS> wsl --shutdown          # sin esto no se aplica
```

### 3. Abrir los puertos en el firewall

En modo espejo el tráfico hacia WSL pasa por el firewall de Windows como cualquier otro. Sin
reglas, WSL comparte la IP pero el firewall corta, y **el síntoma es idéntico a no haber
cambiado nada** — es el fallo que más tiempo hace perder aquí.

```powershell
PS> powershell -ExecutionPolicy Bypass -File \\wsl.localhost\Ubuntu-24.04\home\jaime\mediastack\wsl\08b-red-mirrored.ps1
```

> Los `.ps1` de este repo se lanzan desde Windows pero **viven en la copia de WSL**, que es la
> buena (regla 2 del `CLAUDE.md`). Se llega a ellos por `\\wsl.localhost\Ubuntu-24.04\...`.
> Si Windows se niega a ejecutar desde esa ruta por considerarla de zona no confiable, cópialo
> antes: `copy \\wsl.localhost\Ubuntu-24.04\home\jaime\mediastack\wsl\08b-red-mirrored.ps1 %TEMP%`
> y ejecútalo desde ahí.

Abre solo 2283, 4533 y 8096. Homepage (3000) se queda fuera a propósito: publica en
`127.0.0.1` y se sirve por Caddy.

### 4. Levantar y comprobar

```bash
$ bash ~/mediastack/scripts/arrancar-stack.sh
```

**VERIFICACIÓN 8b:**

- [ ] `bash ~/mediastack/scripts/verificar.sh` sale con **0 fallos** — esto cubre los cuatro
      montajes del NAS, que es lo que había que vigilar.
- [ ] Desde **otro equipo** de la red: `curl -I http://192.168.1.227:2283` responde, y también
      `:4533` y `:8096`.
- [ ] Desde el propio mini PC, `http://localhost:2283` sigue respondiendo.
- [ ] El backup nocturno sigue escribiendo: `bash ~/mediastack/scripts/backup-immich-db.sh` y
      mirar que el volcado llega al NAS.

### Si algo se rompe: vuelta atrás

Quitar `networkingMode=mirrored` de `.wslconfig` y `wsl --shutdown`. Se vuelve al NAT de
siempre; las reglas de firewall que dejó el script son inertes en ese modo y no estorban.

### El «efecto secundario bueno» sobre NFS era falso

Aquí estaba escrito que el modo espejo, al quitar el NAT, dejaría al NAS llamar de vuelta al
cliente y abriría la puerta a montar con `vers=4.1` y bloqueo, en vez del `vers=3,nolock` de
`wsl/fstab.snippet`. **La prueba del 2026-09-02 dice lo contrario**: sin NAT el montaje ni
siquiera se completa, y los cuatro montajes se cayeron. No es que el bloqueo siguiera sin
funcionar: es que se perdió el acceso entero.

Así que esta vía hacia NFSv4.1 queda **descartada, no pendiente**. Si algún día hace falta
bloqueo de ficheros de verdad sobre el NAS, habrá que buscarlo por otro lado. Hoy no hace
falta: sobre el NAS solo hay lecturas y las subidas de Immich, con un único escritor
(`CLAUDE.md` §5, `wsl/fstab.snippet`).

---

## FASE 9 — Acceso desde fuera

> Actualizada el 2026-09-01. La versión anterior de esta fase daba `videos.ruizespana.com`
> apuntando a la IP de Tailscale: **eso ya no es así**. Desde la decisión del 2026-08-31
> (`PLAN.md` §6, `oracle-vps/README.md`) el nombre es `pelis.` y tanto él como `fotos-vpn.`
> son **públicos de verdad** detrás de una VM Oracle Always Free.

**Nada de esta fase se toca hasta que `scripts/verificar.sh` salga con 0 fallos en la LAN.**

**Nombres definitivos y cómo se publica cada uno:**

| Hostname | Servicio | Cloudflare | Quién llega |
|---|---|---|---|
| `fotos.ruizespana.com` | Immich :2283 | Túnel, **proxy naranja** | cualquiera |
| `musica.ruizespana.com` | Navidrome :4533 | Túnel, **proxy naranja** | cualquiera |
| `pelis.ruizespana.com` | Jellyfin :8096 | A **solo DNS (gris)** → IP pública VM Oracle | cualquiera |
| `fotos-vpn.ruizespana.com` | Immich :2283 | A **solo DNS (gris)** → IP pública VM Oracle | cualquiera |
| `casa.ruizespana.com` | Homepage :3000 | A **solo DNS (gris)** → IP Tailscale del mini PC | solo tu tailnet |

`fotos-vpn.` es la URL que se pone en la **app móvil de Immich**: no pasa por Cloudflare, así
que los vídeos de más de 100 MB suben sin chocar con el límite del plan gratuito.

---

### 9a. Quitar `pelis.` del túnel (primero, antes de nada)

Cloudflare Zero Trust → **Networks → Tunnels → MiniPC_Jaime** → *Public Hostnames* → borrar
`pelis.ruizespana.com`. Es justo el tráfico de vídeo que no queremos por el proxy gratuito
(`PLAN.md` §6, aviso 2). El túnel del **NAS** no se toca: es otro túnel, de otra máquina.

### 9b. Tailscale dentro de Ubuntu (no en Windows)

```bash
PS> wsl -d Ubuntu-24.04 -u root -- /home/jaime/mediastack/wsl/09-tailscale.sh
$  sudo tailscale up --hostname=minipc-jrh    # imprime una URL: ábrela e inicia sesión
$  tailscale ip -4                            # anota la 100.x.y.z
```

El porqué de «dentro de Ubuntu» está en la cabecera del propio script y en `PLAN.md` §6:
con `tailscaled` en Windows haría falta `netsh portproxy`, que se rompe con cada
actualización de WSL.

### 9c. Caddy y portal en el mini PC (`casa.`)

```bash
$ cd ~/mediastack/caddy && cp .env.example .env && nano .env
#   TS_IP=100.x.y.z   ← la del paso 9b. Vacío = escucharía en TODAS las interfaces: no.
#   CF_API_TOKEN=...  ← Cloudflare → My Profile → API Tokens → "Edit zone DNS",
#                       acotado a ruizespana.com. Es un secreto: no va al repo.
#   ACME_EMAIL=...
#   El CF_API_TOKEN se puede meter sin que pase por pantalla ni por el historial:
#   bash ~/mediastack/scripts/poner-token-cf.sh   (lo escribe en caddy/.env, modo 600)
$ docker compose up -d --build      # se compila: la imagen oficial no trae el DNS de Cloudflare
$ cd ~/mediastack/homepage && cp .env.example .env && docker compose up -d
```

Registro DNS: `casa` → A **gris** → la IP `100.x.y.z`.

### 9d. VM Oracle para `pelis.` y `fotos-vpn.`

Runbook completo, paso a paso de la consola de OCI incluido: **`oracle-vps/README.md`**.
Resumen, para no perder el hilo:

1. Crear la instancia Always Free (Ubuntu 24.04) y anotar su **IP pública**.
2. Abrir **80/443 en el Security List** de la VCN — *y* dejar que `setup.sh` ponga `ufw`.
   Son dos capas distintas y hacen falta las dos; es el fallo más común aquí.
3. En la VM: `git clone`, y `sudo TAILSCALE_AUTHKEY=tskey-... ./setup.sh`.
4. `cp .env.example .env` con `MINIPC_TS_IP` (la del paso 9b) y `ACME_EMAIL`, y
   `docker compose up -d`.
5. DNS: `pelis` y `fotos-vpn` → A **gris** → **IP pública de la VM** (sustituyen a lo que
   hubiera; si se dejan en naranja, se pierde todo el sentido del montaje).

### 9e. El túnel, al final

`cloudflared/docker-compose.yml` está listo pero **sin levantar**, y `cloudflared/.env` con
`TUNNEL_TOKEN` no existe todavía; hay que crearlo a mano (`scripts/poner-token-cf.sh` **no
sirve aquí**: ese es para el `CF_API_TOKEN` de `caddy/.env`, que es otro token distinto).

```bash
$ cd ~/mediastack/cloudflared
$ install -m 600 /dev/null .env && nano .env    # TUNNEL_TOKEN=...  (Zero Trust → el túnel)
$ docker compose up -d
```

En el túnel solo quedan `fotos.` y `musica.` — `pelis.` se quitó en el paso 9a.

**VERIFICACIÓN 9:**

- [ ] `tailscale status` en el mini PC lo ve como `minipc-jrh`, y desde el móvil con Tailscale
      abre `https://casa.ruizespana.com` **con candado válido** (no aviso de certificado).
- [ ] Desde la VM Oracle: `curl -sI http://<MINIPC_TS_IP>:8096/health` responde — si esto falla,
      lo demás no puede funcionar y el problema es de Tailscale, no de Caddy.
- [ ] Desde datos móviles (**Wi-Fi y Tailscale apagados**): `https://pelis.ruizespana.com` y
      `https://fotos-vpn.ruizespana.com` cargan con certificado válido.
- [ ] Desde datos móviles: la app de Immich apuntando a `https://fotos-vpn.ruizespana.com`
      sube una **foto** y un **vídeo de más de 100 MB**. El vídeo es la prueba que importa:
      es exactamente lo que fallaba por el túnel.
- [ ] `https://fotos.ruizespana.com` y `https://musica.ruizespana.com` siguen abriendo por el
      túnel.
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
