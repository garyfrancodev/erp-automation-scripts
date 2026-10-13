#!/bin/bash
source "$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)/core/lib.sh"

SITE_NAME="${1:-}"
EMAIL="${2:-}"

if [ -z "$SITE_NAME" ] || [ -z "$EMAIL" ]; then
  echo "❌ Debes indicar el nombre del sitio y un correo electrónico. Ejemplo:"
  echo "   bash $(basename "$0") sitio102.erp.mandox.com.bo garyfrancodev@gmail.com"
  exit 1
fi

require_bench
require_cmd certbot "Ejecuta primero scripts/01-server-setup/04-install-dependencies.sh"

if [ ! -d "$BENCH_PATH/sites/$SITE_NAME" ]; then
  echo "❌ El sitio '$SITE_NAME' no existe en $BENCH_PATH/sites. Aborta la configuración de SSL."
  exit 1
fi

# Let's Encrypt valida por HTTP: el dominio debe apuntar ya a este servidor.
# Para omitir esta comprobación: SKIP_DNS_CHECK=1
if [ "${SKIP_DNS_CHECK:-0}" != "1" ]; then
  RESOLVED_IP="$(dig +short A "$SITE_NAME" | tail -n1)"
  if [ "$RESOLVED_IP" != "$SERVER_IP" ]; then
    echo "❌ El DNS de $SITE_NAME resuelve a '${RESOLVED_IP:-nada}', pero este servidor es $SERVER_IP."
    echo "   Espera a que propague el DNS (o usa SKIP_DNS_CHECK=1 para forzar)."
    exit 1
  fi
fi

cd "$BENCH_PATH"

echo "🔒 Habilitando SSL con Let's Encrypt para $SITE_NAME (correo: $EMAIL)..."

# bench no lee ninguna variable para el correo: la cuenta ACME se registra antes con certbot.
# Si ya existe una cuenta, 'register' falla y se continúa con la existente.
sudo certbot register --non-interactive --agree-tos -m "$EMAIL" \
  || echo "ℹ️ Ya existía una cuenta de Let's Encrypt; se reutiliza."

BENCH_BIN="$(command -v bench)"
LE_ARGS=("$SITE_NAME")
if "$BENCH_BIN" setup lets-encrypt --help 2>&1 | grep -q -- '--non-interactive'; then
  LE_ARGS+=(--non-interactive)
fi
sudo "$BENCH_BIN" setup lets-encrypt "${LE_ARGS[@]}"

echo "✅ Certificado SSL configurado correctamente para $SITE_NAME"
echo "📂 Certificados ubicados en: /etc/letsencrypt/live/$SITE_NAME/"
