# auto-albums — álbumes de Immich que se rellenan solos por persona

Immich v3.3 no tiene álbumes automáticos por persona. Sus *Workflows* (desde v3.0) todavía no
filtran por cara ni tienen la acción «añadir a álbum». Este contenedor lo suple con la API
pública de Immich: cada noche busca las fotos y vídeos en los que sale cada persona
configurada y deja el álbum al día.

Inspirado en [immich-face-to-album](https://github.com/romainrbr/immich-face-to-album)
(v1.0.17, revisado el 2026-11-01). Se escribió un script propio por tres motivos:

- usar la forma nueva de búsqueda de v3.2+ (`filter` + `cursor`), porque la plana
  (`personIds`, `page`) está *deprecated*;
- no depender de su modo incremental, que filtra por fecha de **subida** (`createdAfter`)
  y se pierde las caras que se asignan después a fotos antiguas;
- añadir frenos de seguridad al modo espejo.

## Qué hace cada pasada

Para cada álbum de `config.json`:

1. Comprueba que existe cada persona (`GET /api/people/{id}`). Si el nombre no coincide
   con el de la config, avisa en el log.
2. Junta todos los assets donde sale **cualquiera** de las personas. Con
   `"requiere_todas": true` solo cuenta los que tienen a **todas** a la vez. Visibilidad
   `timeline` y `archive`: nunca entra la carpeta bloqueada.
3. Busca el álbum por el id guardado en el estado. Si no lo encuentra, lo busca por nombre;
   si no existe, lo crea en la cuenta de la clave.
4. Añade lo que falte. En `"modo": "espejo"` también **quita lo que sobre**, incluidas las
   fotos añadidas a mano. En `"modo": "anadir"` no quita nunca nada.

Frenos:

- Si la búsqueda no devuelve nada, no se toca el álbum.
- Si hubiera que quitar más del 50 % del álbum, esa pasada no quita nada y lo apunta en el log.
- Cualquier error de la API para ese álbum antes de escribir. Los demás álbumes siguen.

## Ficheros

| Fichero | Qué es |
|---|---|
| `auto_albums.py` | El script. Solo usa la biblioteca estándar de Python 3.10+ |
| `config.json` | Álbumes → personas. **Se relee en cada pasada**: cambiarlo no exige reiniciar |
| `docker-compose.yml` | Contenedor `auto-albums` (`python:3.12-alpine`, sin build, 64 MB) en `mediastack-net` |
| `.env.example` | Plantilla de `.env` (`IMMICH_API_KEY`). `.env` no va al repo |
| `test_auto_albums.py` | 12 pruebas contra un Immich simulado: `python -m unittest test_auto_albums.py` |

Estado (fuera del repo): `/volume1/docker/mediastack-data/auto-albums/estado.json`. Guarda
el nombre de cada álbum con su id y el resultado de la última pasada.

## Álbumes configurados

| Álbum | Personas | Modo |
|---|---|---|
| Papá y Mamá | Jaime Ruiz Cañada **o** Mari Herrero | espejo |
| Papá y Mamá juntos | Jaime Ruiz Cañada **y** Mari Herrero en la misma foto (`requiere_todas`) | espejo |
| Nietos | Guillermo Ruiz España **o** Mía Magallon **o** India Magallon | espejo |

Hora: cada día a las **04:00** (Europe/Madrid), y una pasada al arrancar el contenedor.

## Añadir un álbum

1. Saca el id de la persona: en Immich, *Explorar → Personas →* la persona. Es lo último
   de la URL (`/people/<id>`).
2. Añade una entrada a `albumes` en `config.json` (por PR, como todo el repo).
3. `git pull` en el NAS. La siguiente pasada lo recoge. Para no esperar:
   `docker exec auto-albums python /app/auto_albums.py --una-vez`.

## Clave de API

Tiene que ser del usuario dueño de las personas, que también será el dueño de los álbumes.
Las personas de Immich son por usuario: las de Jaime solo las ve la clave de Jaime.

Immich → avatar → *Ajustes de la cuenta → Claves de API → Nueva clave*, con **solo** estos
permisos:

`person.read`, `asset.read`, `album.read`, `album.create`, `albumAsset.create`, `albumAsset.delete`

Va en `auto-albums/.env` (`chmod 600`, dueño `1026:100`).

## Operación

```bash
cd /volume1/docker/mediastack/auto-albums
docker compose up -d                                              # arrancar
docker logs --tail 50 auto-albums                                 # qué hizo
docker exec auto-albums python /app/auto_albums.py --simular      # ver qué haría, sin escribir
docker exec auto-albums python /app/auto_albums.py --una-vez      # pasada ahora
cat /volume1/docker/mediastack-data/auto-albums/estado.json       # última pasada y su resultado
```

Lo justo de carga: una búsqueda paginada por persona y otra por álbum, sobre la API. No toca
la base de datos ni el disco de fotos.
