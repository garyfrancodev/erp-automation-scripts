#!/bin/bash
set -e

ORIGEN=$1
DESTINO=$2
BENCH_DIR="/home/frappe/frappe-bench"

if [[ -z "$ORIGEN" || -z "$DESTINO" ]]; then
  echo "Uso: ./copy-backup.sh sitio_origen sitio_destino"
  exit 1
fi

cd "$BENCH_DIR"

echo "📁 Copiando archivos de backup de $ORIGEN a $DESTINO..."
cp sites/"$ORIGEN"/private/backups/* sites/"$DESTINO"/private/backups/

echo "✅ Archivos copiados a: sites/$DESTINO/private/backups/"
