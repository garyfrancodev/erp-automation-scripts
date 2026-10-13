#!/bin/bash
source "$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)/core/lib.sh"

SITIO="${1:-}"

if [[ -z "$SITIO" ]]; then
  echo "Uso: ./generate-backup.sh nombre_sitio"
  exit 1
fi

require_user "$FRAPPE_USER"
require_bench
cd "$BENCH_PATH"

if [ ! -d "sites/$SITIO" ]; then
  echo "❌ El sitio '$SITIO' no existe en $BENCH_PATH/sites."
  exit 1
fi

echo "📦 Generando backup de $SITIO..."
bench --site "$SITIO" backup --with-files

echo "✅ Backup generado en: sites/$SITIO/private/backups/"
