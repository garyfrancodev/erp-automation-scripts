#!/bin/bash
source "$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)/core/lib.sh"

ORIGEN="${1:-}"
DESTINO="${2:-}"

if [[ -z "$ORIGEN" || -z "$DESTINO" ]]; then
  echo "Uso: ./copy-backup.sh sitio_origen sitio_destino"
  exit 1
fi

require_user "$FRAPPE_USER"
cd "$BENCH_PATH"

for s in "$ORIGEN" "$DESTINO"; do
  if [ ! -d "sites/$s" ]; then
    echo "❌ El sitio '$s' no existe en $BENCH_PATH/sites."
    exit 1
  fi
done

if ! compgen -G "sites/$ORIGEN/private/backups/*" >/dev/null; then
  echo "❌ El sitio '$ORIGEN' no tiene backups en sites/$ORIGEN/private/backups/."
  exit 1
fi

echo "📁 Copiando archivos de backup de $ORIGEN a $DESTINO..."
mkdir -p "sites/$DESTINO/private/backups"
cp -v sites/"$ORIGEN"/private/backups/* sites/"$DESTINO"/private/backups/

echo "✅ Archivos copiados a: sites/$DESTINO/private/backups/"
