# PLAN — Media stack propio (fotos, música, vídeo) en mini PC Windows

**Fecha:** 2026-08-24 · revisado tras el inventario del equipo
**Autor:** Jaime + Claude
**Estado:** aprobado con Immich sin machine learning (ver §3)

---

## 1. Objetivo y hardware real

Montar tres servicios autoalojados en el **mini PC Windows**, con los **ficheros viviendo en
MaJaNAS** (Synology DS224+, 192.168.1.205):

| Servicio | App | Puerto | Sustituye a |
|---|---|---|---|
| Fotos | **Immich v3** | 2283 | Google Fotos |
| Música | **Navidrome** | 4533 | Spotify (biblioteca propia) |
| Vídeo | **Jellyfin** | 8096 | Plex / Netflix personal |

Después: exposición a Internet vía Cloudflare Tunnel (con matices importantes, §6).

### Equipo (inventario del 24/08/2026, `wsl/inventario.txt`)

| | |
|---|---|
| Nombre | DESKTOP-BNDRMFU · 192.168.1.227 (Wi-Fi) |
| SO | Windows 11 Pro, build 26100 |
| CPU | Intel N150 @ 1.8 GHz · 4 hilos |
| **RAM** | **7,9 GB** |
| Disco | SSD 128 GB · 84,7 GB libres |
| Virtualización | Habilitada en BIOS |

**La RAM manda sobre todo lo demás.** Immich pide **6 GB mínimo y 8 GB recomendado**
([docs oficiales](https://docs.immich.app/install/requirements/)), y esos 8 GB son *para Immich*,
no para el equipo entero. Aquí hay 7,9 GB **con Windows 11 debajo**.

La misma documentación dice que un equipo de 4 GB puede correr Immich **con machine learning
desactivado**, y esa es la decisión tomada: se monta todo, con la búsqueda por caras y por
contenido apagada en horario normal y encendida a ratos, de noche, hasta digerir el histórico
(§3 y anexo ML de `PASOS.md`).

**Lo que se gana y lo que no.** Immich sin ML sigue dando línea de tiempo, álbumes, mapa,
subida automática desde el móvil, compartir y búsqueda por fecha, lugar y nombre de fichero.
Lo que no da mientras el ML está apagado es reconocimiento de caras y búsqueda por contenido
("playa", "perro"), que es justo lo más llamativo frente a Synology Photos. Conviene saberlo
antes de invertir el fin de semana: la diferencia real con lo que ya tienes es menor de lo que
parecía cuando el equipo iba a tener 16 GB.

---

## 2. Decisión de arquitectura: **WSL2 + Docker Engine**, no Docker Desktop

Immich es explícito: *"Linux o sistemas Unix de 64 bits muy recomendados. Entornos no-Linux dan
una experiencia Docker pobre y con soporte limitado"*. Y añade dos restricciones duras:

1. **Postgres no puede vivir en NTFS ni FAT32.**
2. **Los directorios del host montados en WSL bajo `/mnt/c` son incompatibles** con Postgres.
3. **"La base de datos nunca debe estar en un recurso de red de ningún tipo."**

Eso descarta de entrada montar el stack "a lo Windows". La arquitectura correcta es:

```
Windows 11 (mini PC, 16 GB)
└── WSL2 · Ubuntu 24.04 LTS          ← sistema de ficheros ext4 real
    ├── Docker Engine (nativo, apt)   ← NO Docker Desktop
    ├── /var/lib/mediastack/          ← ext4 local: BBDD, config, caché, miniaturas
    │     ├── immich/postgres/        ← Postgres (SSD local, obligatorio)
    │     ├── jellyfin/{config,cache}
    │     └── navidrome/data/         ← SQLite (obligatorio local, ver §4)
    └── /mnt/nas/                     ← NFS contra MaJaNAS: solo ficheros multimedia
          ├── fotos/                  (Immich: subidas nuevas, rw)
          ├── fotos-historico/        (Immich: external library, ro)
          ├── musica/                 (Navidrome, ro)
          └── video/                  (Jellyfin, ro)
```

### Por qué Docker Engine dentro de WSL y no Docker Desktop

| | Docker Engine en WSL2 | Docker Desktop |
|---|---|---|
| Montajes NFS/CIFS del NAS | Directos, el contenedor los ve | Los monta otra distro (`docker-desktop`); hace falta propagación vía `/mnt/wsl`, es la fuente clásica de "el contenedor no ve los ficheros" |
| RAM en reposo | ~300-500 MB | ~1,5-2,5 GB |
| Licencia | Apache 2.0, libre siempre | Gratis solo para uso personal / empresa pequeña. Con Hermanos Ruiz SL de por medio, mejor no depender de ello |
| Arranque automático | Requiere tarea programada (§5) | Automático al iniciar sesión |

El único punto a favor de Docker Desktop es el arranque; se resuelve con una tarea programada
de Windows (documentada en `PASOS.md`, fase 6).

---

## 3. Presupuesto de RAM (7,9 GB reales)

Este es el apartado que decide el diseño. El reparto:

| Componente | RAM | Nota |
|---|---|---|
| Windows 11 en reposo | 2,5 - 3,5 GB | En este equipo, sin nada abierto |
| **Techo de WSL2 (`.wslconfig`)** | **5 GB** | Deja ~3 GB a Windows |
| WSL2 (kernel + Ubuntu + dockerd) | 0,4 GB | |
| `immich-server` | ≤ 2,0 GB | `mem_limit` en el override. Subido de 1,5 el 2026-08-27: se asentaba en 1,1 GB sin biblioteca siquiera |
| `immich_postgres` + `redis` | ≤ 1,0 GB | `mem_limit` |
| `navidrome` | 0,15 GB idle | Hasta ~1 GB en escaneo completo, programado a las 4:00 |
| `jellyfin` | 0,3 GB idle | Un transcode por software sube a ~1,5 GB: hay que evitarlo |
| **Suma en marcha normal** | **~4,0 GB de los 5** | Medido con los cinco contenedores en marcha: 2,5 GB usados de 4,8 |
| `immich-machine-learning` | 2 - 2,5 GB | **Fuera del horario normal.** Solo a demanda, de noche |

Tres medidas, las tres obligatorias en un equipo así:

1. **`memory=5GB` en `.wslconfig`.** Sin límite, WSL reclama hasta el 80% de la RAM y Windows
   pagina. Con 8 GB no hay colchón para equivocarse aquí.
2. **`swap=6GB` en `.wslconfig`.** En un equipo holgado el swap es un lujo; aquí es el
   airbag que evita que el OOM killer mate Postgres en un pico.
3. **Machine learning apagado por defecto** (`profiles: ["ml"]` en el override) y encendido
   con `scripts/ml.sh on` cuando el equipo esté libre. El coste está en el histórico: una vez
   procesado, las fotos nuevas del día a día son un gasto pequeño.

**Y una advertencia de disco.** El SSD es de 128 GB con 84,7 libres. WSL, imágenes Docker,
Postgres y los modelos de ML se llevan unos 25-30 GB. Las miniaturas de Immich van al NAS
(por eso no se activa la optimización opcional de la fase 8c). Vigila que C: no baje de 20 GB
libres: si WSL se queda sin espacio, Postgres se corrompe.

### La alternativa que sigue sobre la mesa

Reinstalar el mini PC como **Ubuntu Server puro** libera los 2,5-3,5 GB de Windows y elimina
toda la capa WSL. En un equipo de 16 GB era un lujo prescindible; en uno de 8 GB es la
diferencia entre tener reconocimiento de caras o no tenerlo. No hace falta decidirlo ahora
—el runbook funciona tal cual— pero si en un mes echas de menos el ML, esa es la salida
antes que comprar RAM (el N150 suele llevarla soldada; conviene abrir y mirar antes de asumir
que se puede ampliar).

---

## 4. Reglas duras de almacenamiento (esto es lo que rompe instalaciones)

| Dato | Dónde | Por qué |
|---|---|---|
| Postgres de Immich | **ext4 local, SSD** | Doc oficial: *"never a network share of any kind"*. Sobre SMB/NFS acaba en corrupción |
| SQLite de Navidrome | **ext4 local** | SQLite sobre CIFS/NFS tiene bloqueo de ficheros poco fiable → corrupción de la BBDD |
| `config` y `cache` de Jellyfin | **ext4 local** | Mismo motivo (SQLite) + rendimiento de miniaturas |
| Fotos, música, vídeo | **NAS** | Es el objetivo del montaje. Volumen grande, acceso secuencial |
| Miniaturas / transcodes de Immich | NAS por defecto; **opcionalmente local** | Suman un 10-20% del tamaño de la biblioteca. En local van mucho más rápidos (§ fase 8, opcional y no oficial) |

### NFS, no SMB

Para los montajes del NAS se usa **NFS** (habilitable en DSM → Panel de control → Servicios de
archivos → NFS):

- Mejor rendimiento con muchos ficheros pequeños (miniaturas, portadas).
- Conserva permisos POSIX (uid/gid), que es lo que Immich pide.
- Sin fichero de credenciales en claro en el mini PC.

Si NFS diera guerra con los permisos de Synology, hay plan B con CIFS documentado en
`PASOS.md` (fase 3, variante B).

---

## 5. Aceleración por hardware (bueno: sí funciona en WSL2)

Immich publica configuraciones **específicas para WSL2** en sus ficheros oficiales:

- `hwaccel.transcoding.yml` → servicio **`vaapi-wsl`** (monta `/dev/dri`, `/dev/dxg` y
  `/usr/lib/wsl`, con `LIBVA_DRIVER_NAME=d3d12`).
- `hwaccel.ml.yml` → servicio **`openvino-wsl`** para la iGPU Intel en machine learning.

Es decir: la iGPU del mini PC se puede aprovechar dentro de WSL2. **Pero**: es una ruta menos
transitada que Linux nativo y depende del modelo de iGPU y del driver de Windows. Por eso el
plan la deja para la **fase 8, opcional**, con el stack ya funcionando en CPU. Nunca se activa
aceleración sobre un montaje que aún no funciona.

Para Jellyfin en WSL2 la aceleración es **más incierta** (no hay configuración oficial WSL como
la de Immich). Se arranca en CPU/Direct Play — que cubre el 90% de los casos si los clientes
son Smart TV, Fire Stick o navegador con códecs compatibles — y se prueba QSV después.

---

## 6. Exposición a Internet: dos avisos serios antes de tocar Cloudflare

**Aviso 1 — El límite de 100 MB de Cloudflare Free.** El plan gratuito corta cualquier petición
con cuerpo mayor de 100 MB. La app móvil de Immich sube cada vídeo en una sola petición: **todo
vídeo de más de 100 MB fallará en la copia de seguridad automática** a través del túnel. Es un
problema conocido y sin solución limpia hoy
([discusión abierta en Immich](https://github.com/immich-app/immich/discussions/25183)).

**Aviso 2 — Streaming de vídeo por el túnel es zona gris de los términos de Cloudflare.**
Servir vídeo pesado por el proxy gratuito ha sido históricamente motivo de aviso. Jellyfin
detrás de Cloudflare Tunnel funciona técnicamente, pero no es lo que Cloudflare quiere ver.

**Recomendación:**

### Nombres definitivos

| Hostname | Servicio | Cómo se publica | Por qué |
|---|---|---|---|
| `fotos.ruizespana.com` | Immich · 2283 | Cloudflare Tunnel (proxy naranja) | Para compartir álbumes con familia que no va a instalarse nada |
| `musica.ruizespana.com` | Navidrome · 4533 | Cloudflare Tunnel (proxy naranja) | Audio, ligero, sin problema de límites |
| `pelis.ruizespana.com` | Jellyfin · 8096 | **Registro DNS «solo DNS» (nube gris) → IP pública de una VM Oracle** | Público de verdad, sin pasar por Cloudflare: ni el límite de 100 MB ni la zona gris de términos aplican |
| `fotos-vpn.ruizespana.com` | Immich · 2283 | **Solo DNS → IP pública de la misma VM Oracle** | Es la URL que se pone en la **app móvil**: sin el límite de 100 MB, los vídeos suben, y ahora también accesible sin Tailscale |
| `casa.ruizespana.com` | Homepage · 3000 | **Solo DNS → IP Tailscale del mini PC** | Portal de entrada/administración; sigue privado a propósito |

La diferencia está en si el tráfico pasa por el proxy de Cloudflare, y si el destino final es
alcanzable desde cualquier sitio o solo desde el tailnet:

- **Naranja (proxy Cloudflare):** accesible desde cualquier sitio sin instalar nada, pero con el
  corte de 100 MB por petición y las limitaciones de contenido pesado.
- **Gris (solo DNS) apuntando a la IP de Tailscale (rango 100.64.0.0/10):** esa IP no es
  enrutable en Internet, así que el nombre solo resuelve útilmente desde tus dispositivos con
  Tailscale. Es acceso privado con nombre bonito, sin abrir un puerto y sin límite de tamaño.
  Es lo que usa `casa.ruizespana.com`.
- **Gris (solo DNS) apuntando a la IP pública de una VM propia (Oracle Cloud Always Free):**
  accesible desde cualquier sitio, como el naranja, pero sin que Cloudflare toque el tráfico —
  así se evitan sus dos avisos sin exigirle tailnet al visitante. El coste: ahora hay un servidor
  propio con IP pública que mantener. Es lo que usan `pelis.` y `fotos-vpn.` desde que hizo
  falta acceso público de verdad (compartir contenido con gente sin Tailscale — p. ej. el
  material de un evento). Detalle completo, runbook y por qué la VM se deja **siempre
  encendida**: `oracle-vps/README.md`.

| Uso | Vía |
|---|---|
| Copia de seguridad del móvil (Immich) | `fotos-vpn.ruizespana.com` → **VM Oracle → Tailscale → mini PC** |
| Ver Jellyfin, incluso compartir con gente sin Tailscale | `pelis.ruizespana.com` → **VM Oracle → Tailscale → mini PC** |
| Compartir un álbum con familia sin instalarles nada | `fotos.ruizespana.com` → **Cloudflare Tunnel** |
| Escuchar música fuera de casa | `musica.ruizespana.com` → **Cloudflare Tunnel** |
| Panel de administración, solo para ti | `casa.ruizespana.com` → **Tailscale** |

### Un registro DNS apunta a una IP, no a un puerto

Detalle que rompe la idea si se pasa por alto: `casa.ruizespana.com → 100.x.y.z` hace que el
nombre resuelva, pero el navegador va al **443**, no al puerto real del servicio. Tal cual, lo
que queda es `casa.ruizespana.com:3000`, sin HTTPS. El mismo problema existe igual apuntando a
una IP pública en vez de a la de Tailscale.

Por eso `casa.ruizespana.com` pasa por un **reverse proxy propio, Caddy** (`caddy/`), que
escucha **solo en la IP del tailnet** y reparte a `localhost:3000`. Los certificados los saca de
Let's Encrypt por el reto **DNS-01 contra Cloudflare**: como `ruizespana.com` es un dominio
público de verdad, el certificado es válido y se renueva solo **sin abrir un solo puerto a
Internet**. La imagen de Caddy se compila (`caddy/Dockerfile`) porque la oficial no trae el
proveedor DNS de Cloudflare.

`pelis.` y `fotos-vpn.` resuelven el mismo problema con la **misma pieza (Caddy), pero en la VM
Oracle** (`oracle-vps/`): ese Caddy sí escucha en el puerto público 80/443 de verdad, así que
puede sacar el certificado por **HTTP-01** normal — no necesita el módulo de Cloudflare ni
compilar nada — y reenvía por Tailscale a `localhost:8096`/`:2283` del mini PC.

Consecuencia de diseño: **Tailscale va dentro de Ubuntu/WSL, no en Windows**. Si `tailscaled`
corriera en Windows, la IP del tailnet sería de Windows y los contenedores están en WSL: el
tráfico llegaría a la IP de Windows, no a `localhost`, el reenvío automático de WSL2 no
serviría y haría falta `netsh portproxy` — una pieza más que se rompe sola con cada
actualización de WSL. La contrapartida es que WSL tiene que estar arrancada, que es justo lo
que garantiza la tarea programada de la fase 6.

Coste en RAM: Caddy ~128 MB y Homepage ~256 MB de techo, sobre los ~3,5 GB de los 5 que ya
gastaba el stack (§3). Sigue quedando margen.

Cloudflare Tunnel entra en **fase 9**, cuando todo lo demás esté verificado. La infraestructura
de túnel ya existente en el NAS no se toca: el mini PC monta su **propio `cloudflared`** en
contenedor, con sus propios hostnames, y los registros de `n8n`, `flota`, `erp` y `mcp` se
quedan como están.

---

## 7. Decisiones que quedan abiertas

1. **Cómo trata Immich las fotos que ya están en el NAS.** Recomendación: **modo mixto** —
   el histórico se indexa como *external library* en solo lectura (respeta tu estructura de
   carpetas y tu regla de no tocar ficheros), y las subidas nuevas del móvil van a la
   biblioteca gestionada. Limitación a saber: en una external library, los álbumes y
   descripciones creados en Immich **no se escriben** a los ficheros, y mover ficheros por
   fuera pierde metadatos al reescanear.
2. **Rutas reales en el NAS** de fotos, música y vídeo. La fase 0 del runbook las inventaría
   antes de escribir nada.

---

## 8. Riesgos y cómo se mitigan

| Riesgo | Mitigación |
|---|---|
| WSL2 no arranca solo tras un corte de luz → servicios caídos sin avisar | Tarea programada de Windows al arrancar + `restart: always` en todos los contenedores + verificación de la fase 6 |
| Postgres acaba en una ruta de red por descuido | `DB_DATA_LOCATION` fijado a ext4 y verificado explícitamente en la fase 5 |
| El primer escaneo se come la RAM y tumba el PC | Límite en `.wslconfig` + escaneo inicial nocturno + Navidrome con escaneo programado, no continuo |
| Pérdida de la BBDD de Immich (los ficheros están a salvo en el NAS, pero álbumes/caras no) | Volcado diario de Postgres al NAS (fase 7), alineado con tu ventana de backup de la 1:00 |
| Deriva entre lo que hay en el PC y lo que hay en git | Todo el stack vive en un repo; **se edita en git y se hace pull en el mini PC**, como en el NAS |

---

## 9. Reglas heredadas que aplican aquí

- **Nada se borra, mueve ni reorganiza sin confirmación explícita.** Vale para el NAS y para
  el mini PC.
- **Si está en GitHub, se cambia primero en git y luego se hace pull.** El repo es la única
  fuente de verdad.
- **Regla que NO aplica aquí:** la de desplegar solo desde Container Manager. Esa es del
  Synology. En el mini PC el despliegue es `docker compose up -d` desde WSL, porque no hay
  registro de DSM que desincronizar.

---

## 10. Fases

| Fase | Qué | Reversible |
|---|---|---|
| 0 | Inventario del mini PC y del NAS | Sí (solo lectura) |
| 1 | WSL2 + Ubuntu + `.wslconfig` | Sí |
| 2 | Docker Engine en WSL | Sí |
| 3 | Montajes NFS del NAS | Sí |
| 4 | Repo `mediastack` en GitHub | Sí |
| 5 | Immich | Sí |
| 6 | Arranque automático | Sí |
| 7 | Navidrome + Jellyfin + backup de BBDD | Sí |
| 8 | *Opcional:* aceleración iGPU, miniaturas en local | Sí |
| 9 | Tailscale + Cloudflare Tunnel | Sí |

Cada fase termina con una verificación que o pasa o no pasa. No se avanza con una fase a medias.
