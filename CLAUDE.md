# CLAUDE.md — reglas para sesiones de Claude Code en este repo

## Qué es esto

Stack multimedia autoalojado de Jaime en el **mini PC Windows (Intel N150, 7,9 GB de RAM)**:
Immich (fotos), Navidrome (música), Jellyfin (vídeo). Los contenedores corren en
**WSL2/Ubuntu**; los ficheros multimedia viven en **MaJaNAS (192.168.1.205)** montado por NFS.

Este repo es **la única fuente de verdad** de la configuración.

## Reglas duras

1. **No borrar, mover ni reorganizar** ningún fichero o carpeta del NAS ni del PC sin
   confirmación explícita de Jaime. Sin excepciones, ni "para limpiar", ni "es temporal".
2. **Una sola copia commitea.** Desde el 2026-09-01 esa copia es **`~/mediastack` dentro de
   WSL**, que es donde corre Claude Code y donde se puede verificar de verdad lo que se cambia.
   `C:\claude\mediastack` queda **congelada**: no se edita ni se commitea desde ahí, y
   desaparece cuando la instalación esté terminada (decisión de Jaime; el borrado lo hace él,
   y antes hay que comprobar que no le queda nada sin commitear:
   `git -C /mnt/c/claude/mediastack status`).
   Lo que no cambia es el fondo de la regla: **nunca dos checkouts divergiendo**. Antes la
   fuente era Windows y WSL solo hacía pull; ahora es al revés.
3. **Ningún secreto en el repo.** `.env`, tokens de túnel, credenciales SMB: fuera. Si
   encuentras uno commiteado, avisa y rota, no lo dejes pasar.
4. **`immich/docker-compose.yml` no se edita jamás.** Es el fichero oficial de la release.
   Todo lo propio va en `immich/docker-compose.override.yml`.
5. **Postgres de Immich, SQLite de Navidrome y config de Jellyfin: siempre en ext4 local**
   (`/var/lib/mediastack/...`). Nunca bajo `/mnt/nas/` ni `/mnt/c/`. Si un cambio mueve
   cualquiera de estos a una ruta de red, es un error grave: párate y avisa.
6. **Montajes del NAS en solo lectura** salvo la carpeta de subidas de Immich y la de backups.
7. **Este repo NO es el NAS.** La regla de "desplegar solo desde Container Manager" es del
   Synology y aquí no aplica: en el mini PC se despliega con `docker compose up -d`.
   Al revés también: no toques la configuración del túnel Cloudflare del NAS desde aquí.

## Antes de dar por hecho un cambio

```bash
bash scripts/verificar.sh
```

Si sale con fallos, el cambio no está terminado. No se cierra una tarea con la verificación
en rojo ni se dice "debería funcionar".

## Contexto de decisiones

- `PLAN.md` — por qué WSL2 + Docker Engine (y no Docker Desktop), presupuesto de RAM,
  reglas de almacenamiento, riesgos de Cloudflare.
- `PASOS.md` — runbook fase a fase con verificaciones.

Si una decisión de `PLAN.md` se cambia, se actualiza `PLAN.md` en el mismo commit.
Documentación desactualizada es peor que no tenerla.
