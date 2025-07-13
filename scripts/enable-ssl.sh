#!/bin/bash
set -e

SITE_NAME="$1"
EMAIL="$2"

if [ -z "$SITE_NAME" ] || [ -z "$EMAIL" ]; then
  echo "❌ Debes indicar el nombre del sitio y un correo electrónico. Ejemplo:"
  echo "   bash enable-ssl.sh sitio102.erp.mandox.com.bo garyfrancodev@gmail.com"
  exit 1
fi

if ! command -v bench &> /dev/null; then
  echo "❌ El comando 'bench' no está disponible. Aborta."
  exit 1
fi

BENCH_PATH="/home/frappe/frappe-bench"
SITE_PATH="$BENCH_PATH/sites/$SITE_NAME"

if [ ! -d "$BENCH_PATH" ]; then
  echo "❌ El directorio de bench '$BENCH_PATH' no existe. Aborta."
  exit 1
fi

if [ ! -d "$SITE_PATH" ]; then
  echo "❌ El sitio '$SITE_NAME' no existe en $SITE_PATH. Aborta la configuración de SSL."
  exit 1
fi

cd "$BENCH_PATH"

echo "🔒 Habilitando SSL con Let's Encrypt para $SITE_NAME con el correo $EMAIL..."

# Usar LETSENCRYPT_EMAIL como variable de entorno
LETSENCRYPT_EMAIL="$EMAIL" bench setup lets-encrypt "$SITE_NAME"

echo "✅ Certificado SSL configurado correctamente para $SITE_NAME"
echo "📂 Certificados ubicados en: /etc/letsencrypt/live/$SITE_NAME/"
