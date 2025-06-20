#!/bin/bash
set -e

SITE_NAME="$1"
EMAIL="$2"

if [ -z "$SITE_NAME" ] || [ -z "$EMAIL" ]; then
  echo "❌ Debes indicar el nombre del sitio y un correo electrónico. Ejemplo:"
  echo "   bash enable-ssl.sh sitio102.erp.mandox.com.bo garyfrancodev@gmail.com"
  exit 1
fi

cd /home/frappe/erpnext-bench

echo "🔒 Habilitando SSL con Let's Encrypt para $SITE_NAME con el correo $EMAIL..."
sudo bench setup lets-encrypt "$SITE_NAME" --email "$EMAIL"

echo "✅ Certificado SSL configurado correctamente para $SITE_NAME"
