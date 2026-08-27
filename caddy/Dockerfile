# Caddy con el módulo DNS de Cloudflare.
#
# La imagen oficial de Caddy NO trae el proveedor DNS de Cloudflare, y sin él no se
# puede usar el reto DNS-01 — que es justo lo que necesitamos: sacar un certificado
# válido para nombres de ruizespana.com SIN exponer el puerto 80 a Internet.
# Por eso se compila. Es el patrón documentado por Caddy (xcaddy).

FROM caddy:2-builder AS builder
RUN xcaddy build --with github.com/caddy-dns/cloudflare

FROM caddy:2
COPY --from=builder /usr/bin/caddy /usr/bin/caddy
