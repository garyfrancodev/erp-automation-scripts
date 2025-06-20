#!/bin/bash
set -e

SITE_NAME="$1"
EMAIL="$2"

if [ -z "$SITE_NAME" ] || [ -z "$EMAIL" ]; then
  echo "❌ Uso incorrecto. Debes indicar el dominio y un email. Ejemplo:"
  echo "   bash enable-ssl.sh erp.miempresa.com admin@miempresa.com"
  exit 1
fi

cd /home/frappe/erpnext-bench

echo "🔒 Configurando correo para Let's Encrypt..."
bench config --set-le "$EMAIL"

echo "🔒 Activando SSL con Let's Encrypt para $SITE_NAME"
sudo bench setup lets-encrypt "$SITE_NAME" --yes

echo "✅ Certificado SSL configurado correctamente para $SITE_NAME"
