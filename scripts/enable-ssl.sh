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

if [ ! -d "/home/frappe/erpnext-bench" ]; then
  echo "❌ El directorio de bench '/home/frappe/erpnext-bench' no existe. Aborta."
  exit 1
fi

cd /home/frappe/erpnext-bench

if ! bench list-sites | grep -q "$SITE_NAME"; then
  echo "❌ El sitio '$SITE_NAME' no existe. Aborta la configuración de SSL."
  exit 1
fi

echo "🔒 Habilitando SSL con Let's Encrypt para $SITE_NAME con el correo $EMAIL..."
bench setup lets-encrypt "$SITE_NAME" --email "$EMAIL"

echo "✅ Certificado SSL configurado correctamente para $SITE_NAME"
echo "📂 Certificados ubicados en: /etc/letsencrypt/live/$SITE_NAME/"
