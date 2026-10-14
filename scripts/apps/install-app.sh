#!/bin/bash
source "$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)/core/lib.sh"

APP_URL="${1:-}"
SITE_NAME="${2:-}"
BRANCH="${3:-${FRAPPE_BRANCH:-version-15}}"

if [ -z "$APP_URL" ]; then
  echo "❌ Uso: erp app install <repo-url-o-nombre> [sitio] [branch]"
  echo "   Ejemplos:"
  echo "     erp app install https://github.com/garyfrancodev/mi-custom-app.git"
  echo "     erp app install https://github.com/garyfrancodev/mi-custom-app.git francosystem.com"
  exit 1
fi

require_bench
cd "$BENCH_PATH"

APP_NAME="$(basename "$APP_URL" .git)"

echo "📦 Obteniendo aplicación '$APP_NAME'..."
if [ -d "apps/$APP_NAME" ]; then
  echo "ℹ️ La app '$APP_NAME' ya existe en el bench. Actualizando con git pull..."
  (cd "apps/$APP_NAME" && git pull) || true
else
  as_frappe bench get-app "$APP_URL" --branch "$BRANCH"
fi

if [ -n "$SITE_NAME" ]; then
  if [ ! -d "sites/$SITE_NAME" ]; then
    echo "❌ El sitio '$SITE_NAME' no existe en $BENCH_PATH/sites."
    exit 1
  fi
  echo "🚀 Instalando '$APP_NAME' en el sitio '$SITE_NAME'..."
  as_frappe bench --site "$SITE_NAME" install-app "$APP_NAME"
  as_frappe bench --site "$SITE_NAME" migrate
fi

echo "🏗️ Compilando assets para '$APP_NAME'..."
as_frappe bench build --app "$APP_NAME" 2>/dev/null || true

echo "🔄 Reiniciando workers..."
sudo supervisorctl restart all 2>/dev/null || true

echo "✅ App '$APP_NAME' configurada correctamente."
