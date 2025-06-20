#!/bin/bash
set -e

# ======================
# 🔧 Parámetros esperados
# ======================

SITE_NAME="$1"
DB_USER="$2"
DB_PASSWORD="$3"
ADMIN_PASSWORD="${ADMIN_PASSWORD:-admin123}"  # puedes parametrizar esto también si quieres

# ======================
# 🚨 Validación de argumentos
# ======================
if [ -z "$SITE_NAME" ] || [ -z "$DB_USER" ] || [ -z "$DB_PASSWORD" ]; then
  echo "❌ Uso incorrecto. Debes proporcionar:"
  echo "   bash create-site.sh <site-name> <db-user> <db-password>"
  echo "   Ejemplo:"
  echo "   bash create-site.sh erp.empresa.com frappe Secreta123!"
  exit 1
fi

# ======================
# 📁 Paths y configuración
# ======================
BENCH_DIR="/home/frappe/erpnext-bench"
cd "$BENCH_DIR"

# ======================
# ❌ Evitar duplicados
# ======================
if bench list-sites | grep -q "$SITE_NAME"; then
  echo "⚠️ El sitio '$SITE_NAME' ya existe. Abortando."
  exit 1
fi

# ======================
# 🏗️ Crear sitio
# ======================
echo "🌐 Creando sitio: $SITE_NAME"
bench new-site "$SITE_NAME" \
  --admin-password "$ADMIN_PASSWORD" \
  --mariadb-root-username "$DB_USER" \
  --mariadb-root-password "$DB_PASSWORD" \
  --no-mariadb-socket

# ======================
# 📦 Instalar apps
# ======================
echo "📦 Instalando apps en $SITE_NAME..."
bench --site "$SITE_NAME" install-app erpnext
bench --site "$SITE_NAME" install-app hrms

echo "✅ Sitio '$SITE_NAME' creado e inicializado correctamente."
