# Oracle VPS — borde público para pelis. y fotos-vpn.

## Por qué existe esto

`pelis.ruizespana.com` (Jellyfin) y `fotos-vpn.ruizespana.com` (Immich, la URL de la app móvil)
estaban pensados como **solo Tailscale** (ver `PLAN.md` §6): sin límite de 100 MB, sin la zona
gris de servir vídeo por el proxy de Cloudflare, pero solo alcanzables desde dispositivos con
Tailscale instalado.

Eso deja de valer en cuanto hace falta que **cualquiera** vea el contenido — por ejemplo, un
evento deportivo cuyo material se cuelga en Immich/Jellyfin y se comparte con gente que no va a
instalarse Tailscale. Exigirles tailnet para eso no es realista.

La solución: una máquina con **IP pública de verdad** hace de borde. Igual que el Caddy del
mini PC (`caddy/`) hoy reparte tráfico del tailnet hacia `localhost`, este Caddy reparte tráfico
público hacia el mini PC **por Tailscale** — el mini PC nunca abre un puerto a Internet, y el
visitante nunca necesita Tailscale.

```
Internet ──▶ DNS (A, nube GRIS) ──▶ IP pública VM Oracle ──▶ Caddy (público, HTTPS)
                                                                     │
                                                          Tailscale (privado)
                                                                     ▼
                                                     mini PC — Jellyfin :8096 / Immich :2283
```

Por qué esto sí evita los dos avisos de `PLAN.md` §6: **no hay Cloudflare de por medio** en
`pelis.` ni `fotos-vpn.` — el DNS es «solo DNS» apuntando directo a la IP de la VM, así que ni el
límite de 100 MB ni los términos de servicio de Cloudflare aplican. El trade-off es el contrario:
ahora hay un servidor propio con IP pública que hay que mantener (parches, certificados,
fail2ban) — de eso trata este directorio.

**Elegido: la VM queda encendida siempre** (decisión de Jaime, 2026-08-31). En el Always Free
Tier de Oracle una instancia encendida 24/7 no cuesta nada, así que no compensa la complejidad
de automatizar alta/baja por evento.

## Qué NO cambia

- `fotos.ruizespana.com` y `musica.ruizespana.com` siguen por Cloudflare Tunnel — audio y fotos
  ligeras, sin problema de límites.
- `casa.ruizespana.com` (portal) sigue **solo Tailscale**, por el Caddy del mini PC. Es un panel
  de administración; no hay motivo para hacerlo público.
- El túnel del NAS (MaJaNAS) no se toca — regla dura del `CLAUDE.md` de este repo.
- Postgres de Immich, SQLite de Navidrome, config de Jellyfin: siguen en ext4 local del mini PC.
  Esta VM no guarda ningún dato de la aplicación, solo hace de proxy.

## 1. Crear la instancia (consola de OCI, a mano)

No hay credenciales de Oracle en esta sesión — esto lo haces tú en console.cloudflare... digo,
en `cloud.oracle.com`:

1. **Compute → Instances → Create instance.**
2. Imagen: **Ubuntu 24.04** (Canonical, no la de Oracle Linux — así todo lo de abajo aplica tal
   cual). Forma: **Always Free** — `VM.Standard.A1.Flex` (Ampere ARM, 1 OCPU/6 GB alcanza de
   sobra para un Caddy) o `VM.Standard.E2.1.Micro` (AMD) si la región no tiene capacidad ARM ese
   día — es el problema conocido de "Out of host capacity" del Always Free, reintentar más tarde
   o cambiar de disponibilidad (AD) suele resolverlo.
3. **Add SSH key**: sube tu clave pública. Sin contraseña, solo llave.
4. Red: deja la VCN/subred por defecto con **IP pública asignada** (`Assign a public IPv4
   address`, marcado).
5. Crear. Anota la IP pública.

### Abrir 80/443 — dos capas, las dos hacen falta

Este es el fallo más común con Oracle: **abrir el Security List no basta**, porque la propia
imagen de Ubuntu trae reglas de `iptables` que bloquean todo salvo el 22.

**Capa 1 — Security List (firewall de la nube):**
`Networking → Virtual Cloud Networks → (tu VCN) → Security Lists → Default Security List` →
`Add Ingress Rules`:
- `0.0.0.0/0`, TCP, puerto destino `80`
- `0.0.0.0/0`, TCP, puerto destino `443`

**Capa 2 — firewall del propio sistema:** lo resuelve `setup.sh` (usa `ufw`, que sustituye las
reglas de `iptables` que trae la imagen). Si algo no conecta después de correr el script,
comprobar aquí antes que en el Security List.

## 2. Conectar y ejecutar `setup.sh`

```bash
ssh ubuntu@<IP_PUBLICA>
```

Copia este directorio a la VM (o clona el repo — el `CLAUDE.md` dice que el repo es la única
fuente de verdad, así que lo más limpio es `git clone` en la VM también):

```bash
sudo apt update && sudo apt install -y git
git clone https://github.com/fundacionhaptica/mediastack.git
cd mediastack/oracle-vps
sudo TAILSCALE_AUTHKEY=tskey-auth-xxxxx ./setup.sh
```

`TAILSCALE_AUTHKEY` sale de la consola de Tailscale: **Settings → Keys → Generate auth key**.
Recomendado: **reusable** (por si hay que rehacer la VM) y **etiquetada** para poder revocarla
sola sin tocar el resto del tailnet. Sin la variable, el script deja `tailscale up` pendiente de
autenticación manual (te da un enlace por pantalla).

El script instala Docker, Tailscale, `ufw` + `fail2ban` + `unattended-upgrades`, y deja el
sistema listo. **No** levanta Caddy todavía — eso es el paso 3, porque antes hace falta saber la
IP de Tailscale del mini PC.

## 3. Levantar Caddy

En el mini PC: `tailscale ip -4` → esa es `MINIPC_TS_IP`.

En la VM:

```bash
cd ~/mediastack/oracle-vps
cp .env.example .env
nano .env   # rellenar MINIPC_TS_IP y ACME_EMAIL
docker compose up -d
docker compose logs -f caddy   # comprobar que saca los certificados sin error
```

A diferencia del Caddy del mini PC (`caddy/`), **este no necesita el módulo DNS de Cloudflare ni
compilar nada**: como escucha en una IP pública de verdad, Let's Encrypt valida por **HTTP-01**
(el reto por defecto), así que la imagen oficial `caddy:2` vale tal cual.

## 4. DNS

En Cloudflare, zona `ruizespana.com`, cambiar (o crear) estos dos registros — **nube GRIS**
(«solo DNS», sin proxy naranja: si se deja naranja, vuelve a pasar por Cloudflare y se pierde
todo el sentido de este montaje):

| Registro | Tipo | Valor |
|---|---|---|
| `pelis` | A | `<IP_PUBLICA_VM_ORACLE>` |
| `fotos-vpn` | A | `<IP_PUBLICA_VM_ORACLE>` |

Antes apuntaban a la IP de Tailscale del mini PC (`100.x.y.z`) — se sustituyen, no se añaden.

## 5. Verificar

```bash
curl -I https://pelis.ruizespana.com
curl -I https://fotos-vpn.ruizespana.com
```

Ambos deben responder con certificado válido y sin pasar por el mini PC directamente (la IP que
resuelve el hostname es la de la VM, no la de Tailscale).

## Mantenimiento

- **Actualizaciones de seguridad**: `unattended-upgrades` las aplica solas; revisar de vez en
  cuando `cat /var/log/unattended-upgrades/unattended-upgrades.log`.
- **Riesgo conocido del Always Free Tier**: Oracle reclama instancias que detecta como inactivas
  ("idle") de verdad ociosas (CPU/red/disco por debajo de un umbral, varios días seguidos). Un
  Caddy sirviendo tráfico real no debería activarlo nunca, pero si la VM va a estar semanas sin
  una sola visita, vale la pena revisar el aviso por correo antes de que caduque el plazo.
- **fail2ban** ya viene con la plantilla de `sshd`; revisar baneos con
  `sudo fail2ban-client status sshd`.
- Esta VM no tiene datos que respaldar: todo el estado real (fotos, vídeos, bases de datos) vive
  en el mini PC y el NAS. Si se pierde, se rehace desde cero con este mismo runbook.
