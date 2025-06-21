#!/bin/bash
set -e

# ======================
# 🔧 Parámetros esperados
# ======================
SUBDOMAIN="$1"
DB_USER="$2"
DB_PASSWORD="$3"
ADMIN_PASSWORD="${ADMIN_PASSWORD:-admin123}"
DOMAIN_NAME="mandox.com.bo"
IP="172.235.142.98"
SITE_NAME="$SUBDOMAIN.$DOMAIN_NAME"
BENCH_DIR="/home/frappe/erpnext-bench"
ERP_DOMAINS_API=$(op read "op://ERP/ERP_DOMAINS/credential")

# ======================
# 🚨 Validación
# ======================
if [ -z "$SUBDOMAIN" ] || [ -z "$DB_USER" ] || [ -z "$DB_PASSWORD" ]; then
  echo "❌ Uso: bash crear-sitio-con-dns.sh <subdominio> <db-user> <db-password>"
  echo "Ej:   bash crear-sitio-con-dns.sh cliente1 frappe Secreta123!"
  exit 1
fi

if ! command -v jq >/dev/null 2>&1; then
  echo "❌ Falta 'jq'. Instálalo con: sudo apt install jq"
  exit 1
fi

# ======================
# 🌐 Crear subdominio en Linode
# ======================
echo "🔎 Buscando dominio '$DOMAIN_NAME'..."
DOMAIN_ID=$(curl -s -H "Authorization: Bearer $ERP_DOMAINS_API" https://api.linode.com/v4/domains \
  | jq -r ".data[] | select(.domain==\"$DOMAIN_NAME\") | .id")

if [ -z "$DOMAIN_ID" ]; then
  echo "❌ Dominio no encontrado en Linode."
  exit 1
fi

echo "🌐 Creando subdominio '$SUBDOMAIN.$DOMAIN_NAME'..."
CREATE_SUBDOMAIN_RESPONSE=$(curl -s -X POST https://api.linode.com/v4/domains/$DOMAIN_ID/records \
  -H "Authorization: Bearer $ERP_DOMAINS_API" \
  -H "Content-Type: application/json" \
  -d "{
    \"type\": \"A\",
    \"name\": \"$SUBDOMAIN\",
    \"target\": \"$IP\",
    \"ttl_sec\": 300
  }")

if echo "$CREATE_SUBDOMAIN_RESPONSE" | jq -e '.errors' >/dev/null; then
  echo "❌ Error al crear subdominio:"
  echo "$CREATE_SUBDOMAIN_RESPONSE" | jq '.errors'
  exit 1
fi
echo "✅ Subdominio '$SUBDOMAIN.$DOMAIN_NAME' creado."

# ======================
# 🏗️ Crear sitio ERPNext
# ======================
cd "$BENCH_DIR"

if [ -d "sites/$SITE_NAME" ]; then
  echo "⚠️ El sitio '$SITE_NAME' ya existe. Abortando."
  exit 1
fi

echo "🌐 Creando sitio ERPNext: $SITE_NAME"
bench new-site "$SITE_NAME" \
  --admin-password "$ADMIN_PASSWORD" \
  --mariadb-root-username "$DB_USER" \
  --mariadb-root-password "$DB_PASSWORD" \
  --mariadb-user-host-login-scope="%"

echo "📦 Instalando apps..."
bench --site "$SITE_NAME" install-app erpnext
bench --site "$SITE_NAME" install-app hrms

# ======================
# 🔐 Ajustar permisos
# ======================
echo "🔐 Ajustando permisos..."
chmod o+x /home/frappe /home/frappe/erpnext-bench /home/frappe/erpnext-bench/sites
chmod o+x "/home/frappe/erpnext-bench/sites/$SITE_NAME"
chmod -R o+rx "/home/frappe/erpnext-bench/sites/$SITE_NAME/public"

echo "✅ Sitio '$SITE_NAME' creado, apps instaladas y subdominio configurado correctamente."
