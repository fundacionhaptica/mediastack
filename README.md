# mediastack

Fotos, música y vídeo autoalojados en **MaJaNAS** (DS224+, 18 GB de RAM), junto a los
ficheros. Hasta el 2026-10-23 corría en el mini PC Windows; ver `PLAN.md` §0.

| App | Qué | URL local |
|---|---|---|
| [Immich](https://immich.app) | Fotos (tipo Google Fotos) | `http://192.168.1.205:2283` |
| [Navidrome](https://navidrome.org) | Música (Subsonic) | `http://192.168.1.205:4533` |
| [Jellyfin](https://jellyfin.org) | Vídeo | `http://192.168.1.205:8096` |

## Por dónde empezar

1. **`HANDOFF.md`** — estado actual y siguiente paso.
2. **`PLAN.md`** — §0 es la decisión de pasar al NAS; el resto, el diseño del mini PC.
3. **`CLAUDE.md`** — reglas para las sesiones de Claude Code sobre este repo.

`PASOS.md`, `wsl/` y los scripts de arranque y montaje son del mini PC: se conservan hasta
retirarlo.

## Comandos del día a día (en el NAS)

```bash
bash /volume1/docker/mediastack/scripts/verificar-nas.sh   # ¿está todo bien?
bash /volume1/docker/mediastack/scripts/ml.sh estado       # caras y búsqueda por contenido
docker stats --no-stream                                   # quién se come la RAM
```

## Dónde vive cada dato

| | Sitio | Se respalda con |
|---|---|---|
| Fotos, música, vídeo | `/volume1/photo`, `music`, `video` | backup del NAS |
| Subidas, miniaturas de Immich | `/volume1/Media` | backup del NAS |
| Postgres de Immich (álbumes, caras) | `/volume1/docker/mediastack-data/immich/postgres` | volcado diario automático de Immich → `/volume1/Media/backups` |
| Config de Jellyfin / Navidrome | `/volume1/docker/mediastack-data/` | backup del NAS (regenerable) |

Los datos de servicio van **fuera del repo** (`/volume1/docker/mediastack`) y nunca en un
recurso de red.
