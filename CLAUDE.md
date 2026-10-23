# CLAUDE.md — reglas para sesiones de Claude Code en este repo

## Qué es esto

Stack multimedia autoalojado de Jaime: Immich (fotos), Navidrome (música), Jellyfin (vídeo).
**Desde el 2026-10-23 corre en MaJaNAS** (Synology DS224+, Celeron J4125, **18 GB de RAM**,
192.168.1.205), junto a los ficheros. Antes corría en el mini PC Windows (WSL2, 7,9 GB): esa
instalación se retira; su historia está en `PLAN.md` y en el historial de git.

Este repo es **la única fuente de verdad** de la configuración. Clon en el NAS:
`/volume1/docker/mediastack`. Antes de tocar el NAS, lee también `/volume1/docker/CLAUDE.md`,
que manda sobre este fichero en todo lo que sea infraestructura compartida.

## Reglas duras

1. **No borrar, mover ni reorganizar** ningún fichero o carpeta del NAS sin confirmación
   explícita de Jaime. Sin excepciones, ni "para limpiar", ni "es temporal".
2. **Los cambios entran por git**: editar en una rama → PR → merge → `git pull` en el NAS.
   No editar a mano en `/volume1/docker/mediastack` "para ir rápido". El MCP del NAS corre
   como root: tras escribir en el clon, devolver la propiedad (`chown -R 1026:100`).
3. **Ningún secreto en el repo.** `.env`, tokens de túnel: fuera. Si encuentras uno
   commiteado, avisa y rota, no lo dejes pasar.
4. **`immich/docker-compose.yml` no se edita jamás.** Es el fichero oficial de la release
   (igual que `hwaccel.*.yml`). Todo lo propio va en `immich/docker-compose.override.yml`.
5. **Datos de servicio fuera del repo**, en `/volume1/docker/mediastack-data/`
   (Postgres de Immich, SQLite de Navidrome, config de Jellyfin). Nunca dentro de
   `/volume1/docker/mediastack`: un `chown`, un `git clean` o un `rsync` sobre el repo los
   rompería (le pasó al PGDATA de flota-db el 2026-09-12). Y nunca en un recurso de red.
6. **Bibliotecas en solo lectura** (`/volume1/photo`, `/volume1/music`, `/volume1/video`).
   La única carpeta en la que escribe el stack es `/volume1/Media` (subidas, miniaturas y
   volcados de Immich).
7. **No crear redes Docker automáticas**: el pool del NAS está agotado. Los tres servicios
   comparten `mediastack-net` (`10.100.5.0/24`, creada a mano, `external: true`).
8. **`compose up` desacoplado**: en este NAS tarda minutos y el MCP corta a los 60 s.
   `setsid nohup sh -c '...' > log 2>&1 < /dev/null &` (el MCP responde `[ERROR]` vacío
   aunque el proceso arranque: comprobar el log, no relanzar).
9. **El disco manda, no la RAM.** El ML de Immich se enciende con `scripts/ml.sh on` solo
   cuando las miniaturas del histórico han terminado. Antes de lanzar algo pesado, mirar el
   iowait (dos lecturas de `/proc/stat`), y no coincidir con la comprobación de datos de los
   domingos.

## Antes de dar por hecho un cambio

```bash
bash /volume1/docker/mediastack/scripts/verificar-nas.sh
```

Si sale con fallos, el cambio no está terminado.

## Contexto de decisiones

- `PLAN.md` — §0 es la decisión de mudarse al NAS (2026-10-23); el resto es el diseño del
  mini PC, que se conserva como historia.
- `HANDOFF.md` — estado actual y siguiente paso.

Si una decisión de `PLAN.md` se cambia, se actualiza `PLAN.md` en el mismo commit.
