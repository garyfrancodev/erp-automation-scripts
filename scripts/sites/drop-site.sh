#!/bin/bash
source "$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)/core/lib.sh"

SITE_NAME="${1:-}"

if [ -z "$SITE_NAME" ]; then
  echo "❌ Uso: erp site drop <dominio-o-subdominio>"
  echo "   Ejemplo: erp site drop francosystem.com"
  exit 1
fi

load_env
DB_USER="${DB_ROOT_USER:-frappe}"
DB_PASSWORD="${DB_ROOT_PASSWORD:-}"

require_bench
cd "$BENCH_PATH"

if [ ! -d "sites/$SITE_NAME" ]; then
  echo "⚠️ El sitio '$SITE_NAME' no existe en $BENCH_PATH/sites."
  exit 0
fi

echo "🗑️ Eliminando sitio '$SITE_NAME' y su base de datos..."
as_frappe bench drop-site "$SITE_NAME" --force --root-password "$DB_PASSWORD" 2>/dev/null || true
sudo rm -rf "sites/$SITE_NAME"

if [ -L "/etc/nginx/conf.d/$BENCH_NAME.conf" ] || [ -f "/etc/nginx/conf.d/$BENCH_NAME.conf" ]; then
  echo "🔁 Regenerando nginx y recargando..."
  as_frappe bench setup nginx --yes
  sudo nginx -t 2>/dev/null && sudo systemctl reload nginx 2>/dev/null || true
fi

echo "✅ Sitio '$SITE_NAME' eliminado correctamente."
