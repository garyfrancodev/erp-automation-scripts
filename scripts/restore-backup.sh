#!/bin/bash
set -e

SITIO=$1
DB_PASSWORD=$2  # contraseña MariaDB del usuario frappe
BENCH_DIR="/home/frappe/erpnext-bench"

if [[ -z "$SITIO" || -z "$DB_PASSWORD" ]]; then
  echo "Uso: ./restore-backup.sh sitio_destino db_password_frappe"
  exit 1
fi

cd "$BENCH_DIR"

echo "🔍 Detectando archivo .sql.gz más reciente..."
SQL_FILE=$(ls -t sites/"$SITIO"/private/backups/*-database.sql.gz | head -n1)
FILES_TAR=$(ls -t sites/"$SITIO"/private/backups/*-files.tar | grep -v "private-files" | head -n1)
PRIVATE_TAR=$(ls -t sites/"$SITIO"/private/backups/*-private-files.tar | head -n1)

echo "♻️ Restaurando base de datos desde $SQL_FILE..."
bench --site "$SITIO" --force restore "$SQL_FILE"

echo "📂 Restaurando archivos públicos..."
tar -xvf "$FILES_TAR" -C sites/"$SITIO"/public/

echo "📂 Restaurando archivos privados..."
tar -xvf "$PRIVATE_TAR" -C sites/"$SITIO"/private/

echo "📚 Instalando dependencias desde requirements.txt..."
bench setup requirements

echo "⚙️ Ejecutando migraciones y build..."
bench --site "$SITIO" migrate
bench build

echo "✅ Restauración completa en $SITIO"
