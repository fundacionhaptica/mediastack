# mediastack

Fotos, música y vídeo autoalojados en el mini PC Windows, con los ficheros en MaJaNAS.

| App | Qué | URL local |
|---|---|---|
| [Immich](https://immich.app) | Fotos (tipo Google Fotos) | `http://<mini-pc>:2283` |
| [Navidrome](https://navidrome.org) | Música (Subsonic) | `http://<mini-pc>:4533` |
| [Jellyfin](https://jellyfin.org) | Vídeo | `http://<mini-pc>:8096` |

## Por dónde empezar

1. **`PLAN.md`** — arquitectura, decisiones y por qué. Léelo entero una vez.
2. **`PASOS.md`** — el runbook. Fases 0 a 9, cada una con su verificación.
3. **`CLAUDE.md`** — reglas para las sesiones de Claude Code sobre este repo.

## Estructura

```
mediastack/
├── PLAN.md · PASOS.md · CLAUDE.md
├── immich/       docker-compose.override.yml + .env.example
│                 (el docker-compose.yml oficial se descarga, no se versiona editado)
├── navidrome/    docker-compose.yml
├── jellyfin/     docker-compose.yml + override de iGPU (opcional)
├── cloudflared/  docker-compose.yml   (fase 9)
├── wsl/          .wslconfig, wsl.conf, fstab.snippet
└── scripts/      verificar.sh · arrancar-stack.sh · backup-immich-db.sh
```

## Comandos del día a día

```bash
bash scripts/verificar.sh          # ¿está todo bien?
bash scripts/arrancar-stack.sh     # levantar todo
docker stats --no-stream           # quién se come la RAM
```

## Dónde vive cada dato

| | Sitio | Se respalda con |
|---|---|---|
| Fotos, música, vídeo | NAS | backup del NAS (1:00) |
| Postgres de Immich (álbumes, caras) | ext4 local del mini PC | `scripts/backup-immich-db.sh` → NAS |
| Config de Jellyfin / Navidrome | ext4 local del mini PC | pendiente (regenerable) |

Las bases de datos **nunca** van al NAS: Immich lo prohíbe explícitamente y SQLite sobre
red se corrompe.
