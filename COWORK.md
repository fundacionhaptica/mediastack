# Fases para terminar la instalación con Claude Cowork

Guion para completar con **Claude Cowork** lo que queda tras la mudanza al NAS (2026-10-23):
los asistentes de las tres apps, el paso de los dominios al túnel del NAS y la retirada del
mini PC. Cada fase lleva el **texto que se pega en Cowork**, lo que haces **tú** y cómo se
comprueba que quedó bien.

## Reglas para Cowork (van en todas las fases)

Pega esto **una vez** al principio de la conversación de Cowork:

```
Vas a ayudarme a terminar la instalación de mi stack multimedia (Immich, Navidrome,
Jellyfin) en mi NAS Synology 192.168.1.205. Reglas:
1. Contraseñas y correos de las cuentas los escribo YO. Tú te paras en ese campo y me avisas.
2. No borres nada ni pulses "Eliminar"/"Delete" sin preguntarme antes, aunque el paso lo diga.
3. Antes de dar un paso por hecho, haz una captura y dime qué ves.
4. Si algo no coincide con lo que te digo (un botón no está, un error), PARA y cuéntamelo.
   No improvises otra ruta.
5. Ve fase a fase: al acabar cada una, resume qué quedó hecho y espera mi "sigue".
```

Cowork necesita el navegador (Claude en Chrome o el uso del ordenador). Hazlo **desde un
equipo de casa** (misma red que el NAS): las direcciones `192.168.1.205` no funcionan desde
fuera. El orden importa: las fases 1-3 antes que la 4, y la 6 la última.

---

## Fase 1 — Immich (fotos)

**Cuándo:** cualquier momento para el asistente. El **escaneo** del paso 1.4 lánzalo **por la
noche**: son más de 200.000 ficheros y ocupa los discos horas. Nunca un domingo (ese día el NAS
hace su comprobación de datos y ya va cargado).

**Texto para Cowork:**

```
Fase 1: Immich. Abre http://192.168.1.205:2283
1.1 Asistente de bienvenida: crea la cuenta de administrador. Para en los campos de
    correo, contraseña y nombre: los escribo yo.
1.2 Ve a Administración → Ajustes → Machine Learning y DESACTIVA el machine learning
    (interruptor general). Guarda. Motivo: el contenedor de ML está apagado a propósito
    hasta que terminen las miniaturas; si se queda activado, los trabajos fallan en bucle.
1.3 En Administración → Ajustes → Transcodificación de vídeo → Aceleración por hardware,
    elige "Quick Sync" (QSV). Guarda.
1.4 Administración → Bibliotecas externas → Crear biblioteca. Propietario: mi usuario.
    Ruta de importación: /fotos-historico  (exactamente así). Deja los patrones de
    exclusión que vienen por defecto (@eaDir, #recycle, ._*). Guarda, pero NO pulses
    "Escanear" todavía: pregúntame antes, quiero lanzarlo de noche.
1.5 Hazme una captura de Administración → Trabajos y dime qué colas hay activas.
```

**Tú:** escribes correo y contraseña, y decides cuándo escanear.

**Bien hecho si:** entras con tu usuario; la biblioteca externa aparece con la ruta
`/fotos-historico`; tras escanear, la cola **"Generar miniaturas"** empieza a crecer.

**Avísame a mí (Claude Code)** cuando "Generar miniaturas" llegue a 0 pendientes: entonces
enciendo el ML (`scripts/ml.sh on`) y lo vuelves a activar en el paso 1.2.

---

## Fase 2 — Navidrome (música)

**Texto para Cowork:**

```
Fase 2: Navidrome. Abre http://192.168.1.205:4533
2.1 Te pedirá crear el primer usuario (será administrador). Para en usuario y
    contraseña: los escribo yo.
2.2 Entra y comprueba que aparece música en "Álbumes". Si sale vacío, ve al menú de
    usuario → "Escanear biblioteca" (scan) y espera un par de minutos.
2.3 Dime cuántos álbumes y artistas ves.
```

**Tú:** usuario y contraseña.

**Bien hecho si:** ves álbumes (hay unas 6.300 pistas, incluidos audiolibros).

---

## Fase 3 — Jellyfin (vídeo)

> ✅ **Hecha el 2026-10-24 desde Claude Code, por la API** (ver `HANDOFF.md`). Solo queda
> cambiar la contraseña temporal del usuario `jaime`.

**Texto para Cowork:**

```
Fase 3: Jellyfin. Abre http://192.168.1.205:8096
3.1 Asistente: idioma Español. Crea el usuario administrador (usuario y contraseña los
    escribo yo).
3.2 Bibliotecas, crea dos:
    - Tipo "Películas", nombre "Películas", carpeta /media/Peliculas
    - Tipo "Vídeos caseros y fotos", nombre "Vídeos", carpeta /media
      (en esta, quita la carpeta Peliculas si te deja excluirla; si no, déjalo así)
    Idioma de metadatos: Español, país: España.
3.3 Acceso remoto: deja "Permitir conexiones remotas" marcado. NO actives el mapeo
    automático de puertos (UPnP).
3.4 Termina el asistente y entra.
3.5 Panel de control → Reproducción → Transcodificación:
    - Aceleración por hardware: "Intel QuickSync (QSV)"
    - Dispositivo: /dev/dri/renderD128
    - Marca descodificación por hardware para: H264, HEVC, HEVC 10bit, VP9, MPEG2, VC1
    - Deja DESMARCADO "codificador de baja potencia" (low-power)
    Guarda.
3.6 Reproduce 10 segundos de cualquier vídeo y, en Panel → Panel de control → Actividad,
    dime si aparece "Transcodificando" y con qué (busca "QSV" o "hardware").
```

**Tú:** usuario y contraseña.

**Bien hecho si:** las dos bibliotecas muestran vídeos y la reproducción arranca. Si con QSV
el vídeo no arranca, vuelve a poner aceleración "Ninguna" y me avisas: no es grave, convierte
por CPU.

---

## Fase 4 — Dominios al túnel del NAS (Cloudflare Zero Trust)

Hoy `fotos.` y `musica.ruizespana.com` apuntan al túnel **MiniPC_Jaime** (el mini PC), y
`pelis.` también. Hay que pasar los dos primeros al túnel del NAS, **Synology-MaJa**.
`pelis.` **no** se pasa: Jellyfin por el proxy de Cloudflare queda en zona gris de sus
términos (decisión del 2026-08-27).

**Texto para Cowork:**

```
Fase 4: Cloudflare. Abre https://one.dash.cloudflare.com → Networks → Tunnels.
(El login lo hago yo.)
4.1 Abre el túnel "MiniPC_Jaime" → pestaña "Public Hostname" (o "Published application
    routes"). Hazme captura de la lista y NO toques nada aún.
4.2 Cuando te diga "sigue": borra de ese túnel las rutas fotos.ruizespana.com,
    musica.ruizespana.com y pelis.ruizespana.com (pregúntame antes de cada borrado).
4.3 Abre el túnel "Synology-MaJa" → Public Hostname → Añadir:
    - Subdominio fotos, dominio ruizespana.com, tipo HTTP, URL 192.168.1.205:2283
    - Subdominio musica, dominio ruizespana.com, tipo HTTP, URL 192.168.1.205:4533
    OJO: tipo HTTP, nunca HTTPS (con HTTPS da 502).
    Si dice que ya existe un registro DNS para ese nombre, PARA y avísame.
4.4 Abre en una pestaña nueva https://fotos.ruizespana.com y https://musica.ruizespana.com
    y dime si sale la pantalla de login de cada app.
```

**Tú:** el login de Cloudflare y el "sí" a cada borrado.

**Bien hecho si:** las dos direcciones abren el login de Immich y de Navidrome desde fuera
de casa (prueba con el móvil sin Wi-Fi).

**Para la app de Immich del móvil:** servidor `https://fotos.ruizespana.com`. Ojo: Cloudflare
corta las subidas de más de **100 MB** por fichero, así que los vídeos largos subidos desde
fuera de casa fallarán. En casa, usa `http://192.168.1.205:2283`.

---

## Fase 5 — Comprobación final (Claude Code, no Cowork)

Escríbeme por aquí y lanzo:

```bash
bash /volume1/docker/mediastack/scripts/verificar-nas.sh
```

Tiene que salir **0 fallos**. Si sale bien, pasas a la fase 6.

---

## Fase 6 — Retirar el mini PC (IRREVERSIBLE)

Hazlo **en el propio mini PC**, con Cowork abierto allí. Nada del mini PC hay que conservarlo:
su Immich nunca tuvo usuario y las fotos están en el NAS. Pero el paso 6.3 **borra la
instalación de Ubuntu entera** y no tiene vuelta atrás, así que **los comandos los ejecutas tú**:
Cowork te guía y comprueba.

**Texto para Cowork:**

```
Fase 6: retirar el stack del mini PC. Estoy en el mini PC (Windows). Los comandos los
ejecuto yo en PowerShell como administrador; tú me dices cuál toca y miras el resultado.
6.1 Comprobar que no queda trabajo sin subir a GitHub:
      wsl -d Ubuntu-24.04 -- git -C /home/jaime/mediastack status --short
      git -C C:\claude\mediastack status --short
    Si alguno saca líneas, PARA: hay cambios sin subir.
6.2 Quitar la tarea de arranque automático:
      Unregister-ScheduledTask -TaskName MediaStack -Confirm:$false
6.3 Borrar Ubuntu de WSL (contenedores, imágenes, ~30 GB). IRREVERSIBLE: pídeme
    confirmación explícita antes:
      wsl --shutdown
      wsl --unregister Ubuntu-24.04
6.4 Borrar la copia vieja del repo y la configuración de WSL:
      Remove-Item -Recurse -Force C:\claude\mediastack
      Remove-Item C:\Users\Admin\.wslconfig
6.5 Comprueba con  wsl -l -v  que Ubuntu-24.04 ya no aparece, y dime cuánto espacio libre
    queda en C:.
6.6 En Cloudflare Zero Trust → Networks → Tunnels: borrar el túnel "MiniPC_Jaime"
    (pregúntame antes). Si dice que tiene conectores activos, PARA.
```

**Bien hecho si:** `wsl -l -v` no lista Ubuntu-24.04, C: ha ganado ~30 GB y el túnel
MiniPC_Jaime ya no existe.

---

## Fase 7 — Cierre (Claude Code)

Avísame cuando acabes la fase 6 y:

- quito del repo lo que solo servía al mini PC (`wsl/`, `PASOS.md`, scripts de WSL, `caddy/`,
  `oracle-vps/`, etc.; los que tengan dudas te los pregunto);
- y, cuando terminen las miniaturas, enciendo el ML de Immich.
