# Migración de fotos a Immich

Google Fotos (Takeout) e iCloud de cuatro personas → cada una en su cuenta de Immich.

| Persona | iCloud (web de acceso) | Carpeta en el NAS |
|---|---|---|
| Jaime | `http://192.168.1.205:8410` | `/volume1/Media/_migracion/icloud/jaime` |
| María España | `:8411` | `.../icloud/maria-espana` |
| María Herrero | `:8412` | `.../icloud/maria-herrero` |
| María Jesús Morales | `:8413` | `.../icloud/maria-jesus` |
| Takeout de Jaime | — | `/volume1/Media/_migracion/takeout/jaime` (ZIP sin descomprimir) |

## iCloud

1. Rellenar los `APPLE_ID_*` en `.env`.
2. `docker compose up -d` (desacoplado, regla 8).
3. Abrir la web de cada cuenta, meter contraseña de Apple y código de verificación.
   Requisitos en el iPhone: *Protección avanzada de datos* desactivada y *Acceder a los
   datos de iCloud en la web* activado. Apple caduca la sesión cada ~2 meses: repetir el paso 3.
4. icloudpd descarga y vuelve a mirar cada 6 h. Nunca borra nada de iCloud.

## Importar a Immich

Con la clave de API de cada usuario en `.env` (`IMMICH_KEY_*`):

```bash
./importar.sh jaime takeout --dry-run   # simulación primero
./importar.sh jaime takeout
./importar.sh maria-jesus icloud
```

Logs en `/volume1/Media/_migracion/logs/`. Lanzar de noche (regla 9).

## Duplicados

Immich descarta al subir los ficheros idénticos. Los parecidos (misma foto entre Google e
iCloud, comprimida o sin metadatos) aparecen en *Utilidades → Duplicados* cuando el ML
está encendido (`scripts/ml.sh on`).

## Borrar el origen

Solo cuando el recuento en Immich cuadre. Google Fotos se borra a mano (la API no lo
permite). Las descargas de `_migracion` se borran solo con confirmación de Jaime (regla 1).