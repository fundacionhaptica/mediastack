# HANDOFF — estado del stack a 2026-10-23 (ya en el NAS)

Documento de traspaso: lo que está hecho, lo que falta y el siguiente paso exacto. El estado
del mini PC (fases 0-9 en WSL) está en el historial de git de este fichero, hasta el commit
`7f90a0e`.

Máquina: **MaJaNAS**, DS224+ (Celeron J4125), **18 GB de RAM** desde el 2026-10-23,
192.168.1.205. Clon del repo: `/volume1/docker/mediastack`. Datos de servicio:
`/volume1/docker/mediastack-data`.

---

## Hecho y verificado (2026-10-23, 23:01 UTC)

| | Estado | Detalle |
|---|---|---|
| RAM nueva | ✅ | DSM ve 17,4 GiB; ~12,5 GB libres con todo el resto del NAS en marcha |
| Red | ✅ | `mediastack-net`, `10.100.5.0/24` (el pool automático está agotado) |
| Immich v3.3.5 | ✅ `healthy` | server + postgres + redis. ML **no creado** (perfil `ml`, a propósito) |
| Navidrome | ✅ `healthy` | lee `/volume1/music` (6.333 ficheros) |
| Jellyfin | ✅ `healthy` | lee `/volume1/video` (682 ficheros), con `/dev/dri` y grupo 937 |
| Puertos | ✅ | 2283, 4533, 8096 responden 200 en `192.168.1.205` |

Tiempos medidos: descargar las cinco imágenes, **~6 min**; primer arranque de Immich hasta
`healthy`, **~8 min** (migraciones de una base nueva sobre disco mecánico).

## Lo que falta, en este orden

### 1. Asistentes iniciales (Jaime, en el navegador, desde cualquier equipo de la LAN)

- **Immich** `http://192.168.1.205:2283` — crear el admin. Luego *Administración →
  Bibliotecas externas* → nueva biblioteca con la ruta **`/fotos-historico`** (es
  `/volume1/photo`, en solo lectura). Lanzar el escaneo **de noche**: son 200.000+ ficheros y
  sacar sus miniaturas ocupa los discos horas.
- **Jellyfin** `http://192.168.1.205:8096` — asistente; biblioteca apuntando a **`/media`**.
  Luego *Panel → Reproducción → Transcodificación* → **Intel QuickSync (QSV)**.
- **Navidrome** `http://192.168.1.205:4533` — crear el usuario; el primer escaneo es solo.

### 2. Encender el ML de Immich (caras y búsqueda por contenido)

Cuando en *Administración → Trabajos* "Generar miniaturas" ya no tenga pendientes:

```bash
bash /volume1/docker/mediastack/scripts/ml.sh on
```

y activar *Administración → Ajustes → Machine Learning*. Con 18 GB cabe siempre; se aplaza
solo por el disco (`PLAN.md` §0).

### 3. Volver a publicar fuera (Cloudflare) — decisión y acción de Jaime

El túnel **MiniPC_Jaime** sigue apuntando al mini PC (`fotos.`, `musica.` y `pelis.` →
`localhost` del mini PC). Al retirar el mini PC esos nombres dejan de responder. Lo natural es
pasarlos al túnel del NAS (**Synology-MaJa**, contenedor `cloudflare-maja-2`), **siempre en
HTTP**:

| Hostname | Servicio en el NAS |
|---|---|
| fotos.ruizespana.com | `http://192.168.1.205:2283` |
| musica.ruizespana.com | `http://192.168.1.205:4533` |

`pelis.` (Jellyfin) **no** va por Cloudflare: lo decidido el 2026-08-27 sigue valiendo (vídeo
por el proxy gratuito, zona gris de sus términos). Ver `PLAN.md` §6.

### 4. Retirar el mini PC (decidido por Jaime el 2026-10-23, cuando el NAS esté verificado)

Desde la nube no se llega al mini PC, así que esto lo hace Jaime en el propio equipo, en
PowerShell como administrador. **Nada del mini PC tiene datos que conservar**: su Immich nunca
tuvo usuario y las bibliotecas están en el NAS.

```powershell
# 0. Comprobar que no queda nada sin subir en las dos copias del repo
wsl -d Ubuntu-24.04 -- git -C /home/jaime/mediastack status --short
git -C C:\claude\mediastack status --short

# 1. Quitar la tarea de arranque automático
Unregister-ScheduledTask -TaskName MediaStack -Confirm:$false

# 2. Borrar la distribución de WSL entera (contenedores, imágenes, ~30 GB). IRREVERSIBLE.
wsl --shutdown
wsl --unregister Ubuntu-24.04

# 3. La copia congelada del repo y la config de WSL
Remove-Item -Recurse -Force C:\claude\mediastack
Remove-Item C:\Users\Admin\.wslconfig
```

Y en Cloudflare Zero Trust, borrar el túnel **MiniPC_Jaime** después del paso 3 de arriba.

Hecho eso, se quitan del repo los ficheros que solo servían al mini PC: `wsl/`, `PASOS.md`,
`scripts/{verificar,arrancar-stack,boot-mediastack,montar-nas,backup-immich-db}.sh`,
`jellyfin/docker-compose.hwaccel-wsl.yml.example`, y se decide qué hacer con `caddy/`,
`homepage/`, `cloudflared/` y `oracle-vps/` (fase 9 del mini PC, aparcada).

---

## Trampas de esta instalación (no volver a tropezar)

- **ACL de Synology y contenedores.** Con `user: 1026:100` (jaime:users), Navidrome no podía
  escribir en su carpeta ni leer `/volume1/music`, y Jellyfin moría con código 139. A jaime le
  da acceso su grupo **administrators (101)**, que un contenedor no hereda. Arreglado con
  `group_add: ["101"]`. Los bits POSIX (`d---------`, `dr-xr-xr-x`) no dicen nada: probar con
  `docker run --rm --user 1026:100 --group-add 101 -v ...:/x alpine touch /x/p`.
- **`setsid nohup ... &` desde el MCP del NAS** devuelve `[ERROR]` sin texto, pero el proceso
  arranca. Comprobar el log; relanzar sería hacer el trabajo dos veces.
- **Docker deja de contestar a ratos** (arranque en frío del NAS, contenedores en bucle de
  reinicio). Los contenedores siguen sirviendo. Un contenedor propio en bucle se para antes de
  diagnosticar: carga al daemon.
- **Las carpetas compartidas (`/volume1/photo`…) no están montadas en `nas-mcp`**: se miran con
  un contenedor de usar y tirar (`docker run --rm -v /volume1/photo:/x:ro alpine ls /x`). Un
  `du` sobre 200.000 ficheros no acaba en el minuto del MCP, y el contenedor sigue vivo
  después del corte: pararlo.

## Comprobación

```bash
bash /volume1/docker/mediastack/scripts/verificar-nas.sh
```
