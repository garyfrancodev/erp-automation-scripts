#!/bin/bash
set -e

SITIO=$1
BENCH_DIR="/home/frappe/erpnext-bench"

if [[ -z "$SITIO" ]]; then
  echo "Uso: ./generate-backup.sh nombre_sitio"
  exit 1
fi

cd "$BENCH_DIR"

echo "📦 Generando backup de $SITIO..."
bench --site "$SITIO" backup --with-files

echo "✅ Backup generado en: sites/$SITIO/private/backups/"
