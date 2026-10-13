#!/bin/bash
source "$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)/core/lib.sh"

SITIO="${1:-}"

if [[ -z "$SITIO" ]]; then
  echo "Uso: ./restore-backup.sh sitio_destino"
  exit 1
fi

require_user "$FRAPPE_USER"
require_bench
cd "$BENCH_PATH"

BACKUP_DIR="sites/$SITIO/private/backups"
if [ ! -d "$BACKUP_DIR" ]; then
  echo "❌ No existe $BENCH_PATH/$BACKUP_DIR (¿sitio inexistente? ¿ejecutaste copy-backup.sh?)."
  exit 1
fi

echo "🔍 Detectando el backup de base de datos más reciente..."
# shellcheck disable=SC2012
SQL_FILE="$(ls -t "$BACKUP_DIR"/*-database.sql.gz 2>/dev/null | head -n1 || true)"
if [ -z "$SQL_FILE" ]; then
  echo "❌ No hay archivos *-database.sql.gz en $BACKUP_DIR."
  exit 1
fi

# Los demás archivos se emparejan por el prefijo (fecha + sitio) del .sql.gz elegido,
# así nunca se mezclan archivos de backups distintos.
PREFIX="${SQL_FILE%-database.sql.gz}"
FILES_TAR="$PREFIX-files.tar"
PRIVATE_TAR="$PREFIX-private-files.tar"
CONFIG_JSON="$PREFIX-site_config_backup.json"

# Credenciales root de MariaDB (restore las necesita; si no, pregunta por consola).
load_env
RESTORE_ARGS=()
if [ -n "${DB_ROOT_USER:-}" ] && [ -n "${DB_ROOT_PASSWORD:-}" ]; then
  if bench --site "$SITIO" restore --help 2>&1 | grep -q -- '--db-root-username'; then
    RESTORE_ARGS+=(--db-root-username "$DB_ROOT_USER" --db-root-password "$DB_ROOT_PASSWORD")
  else
    RESTORE_ARGS+=(--mariadb-root-username "$DB_ROOT_USER" --mariadb-root-password "$DB_ROOT_PASSWORD")
  fi
fi
[ -f "$FILES_TAR" ]   && RESTORE_ARGS+=(--with-public-files "$FILES_TAR")   || echo "⚠️ Sin archivos públicos para este backup."
[ -f "$PRIVATE_TAR" ] && RESTORE_ARGS+=(--with-private-files "$PRIVATE_TAR") || echo "⚠️ Sin archivos privados para este backup."

echo "♻️ Restaurando base de datos y archivos desde $SQL_FILE..."
bench --site "$SITIO" --force restore "$SQL_FILE" "${RESTORE_ARGS[@]}"

# Sin el encryption_key original, las contraseñas cifradas (correo, integraciones) quedan inservibles.
if [ -f "$CONFIG_JSON" ]; then
  ENC_KEY="$(jq -r '.encryption_key // empty' "$CONFIG_JSON")"
  if [ -n "$ENC_KEY" ]; then
    echo "🔑 Restaurando encryption_key del sitio de origen..."
    bench --site "$SITIO" set-config encryption_key "$ENC_KEY"
  fi
else
  echo "⚠️ No se encontró $CONFIG_JSON: no se restauró el encryption_key."
fi

echo "📚 Instalando dependencias desde requirements.txt..."
bench setup requirements

echo "⚙️ Ejecutando migraciones y build..."
bench --site "$SITIO" migrate
bench build

# Solo aplica si hay producción configurada; si no hay procesos que reiniciar, no es un error.
bench restart || echo "ℹ️ 'bench restart' omitido (¿sin producción configurada?)."

echo "✅ Restauración completa en $SITIO"
