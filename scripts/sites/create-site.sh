#!/bin/bash
source "$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)/core/lib.sh"

# Uso: bash create-site.sh <subdominio> [db-user db-password]
#   - db-user / db-password son opcionales: por defecto se leen de .env (DB_ROOT_USER / DB_ROOT_PASSWORD).
#   - ADMIN_PASSWORD (variable de entorno) es opcional: si no se indica se genera una aleatoria.
SUBDOMAIN="${1:-}"

if [ -z "$SUBDOMAIN" ]; then
  echo "❌ Uso: bash $(basename "$0") <subdominio> [db-user db-password]"
  echo "   Ej:  bash $(basename "$0") cliente1"
  exit 1
fi

load_env
DB_USER="${2:-${DB_ROOT_USER:-}}"
DB_PASSWORD="${3:-${DB_ROOT_PASSWORD:-}}"
if [ -z "$DB_USER" ] || [ -z "$DB_PASSWORD" ]; then
  echo "❌ No hay credenciales de MariaDB. Ejecuta install-mariadb.sh o pásalas como 2º y 3er argumento."
  exit 1
fi

SITE_NAME="$SUBDOMAIN.$DOMAIN_NAME"
ADMIN_KEY="ADMIN_PASSWORD_${SUBDOMAIN^^}"
ADMIN_KEY="${ADMIN_KEY//[^A-Z0-9_]/_}"
ADMIN_GENERATED=false
if [ -z "${ADMIN_PASSWORD:-}" ]; then
  ADMIN_PASSWORD="$(gen_password)"
  ADMIN_GENERATED=true
fi

require_bench
require_cmd jq "Instálalo con: sudo apt install jq"
require_cmd curl

if [ -d "$BENCH_PATH/sites/$SITE_NAME" ]; then
  echo "⚠️ El sitio '$SITE_NAME' ya existe. Abortando."
  exit 1
fi

# Token de Linode: variable de entorno ERP_DOMAINS_API o 1Password.
if [ -z "${ERP_DOMAINS_API:-}" ]; then
  require_cmd op "Define ERP_DOMAINS_API o instala/configura 1Password CLI."
  ERP_DOMAINS_API="$(op read "$OP_DOMAINS_REF")"
fi

# El token se pasa por un archivo temporal de curl (-K) para que no aparezca en 'ps'.
linode_api() {
  local method="$1" path="$2" body="${3:-}"
  local args=(-sS -X "$method" -K <(printf 'header = "Authorization: Bearer %s"\n' "$ERP_DOMAINS_API"))
  if [ -n "$body" ]; then
    args+=(-H "Content-Type: application/json" -d "$body")
  fi
  curl "${args[@]}" "https://api.linode.com/v4$path"
}

# ======================
# 🌐 Crear subdominio en Linode
# ======================
echo "🔎 Buscando dominio '$DOMAIN_NAME'..."
DOMAIN_ID="$(linode_api GET "/domains?page_size=500" \
  | jq -r --arg d "$DOMAIN_NAME" '.data[]? | select(.domain==$d) | .id')"

if [ -z "$DOMAIN_ID" ]; then
  echo "❌ Dominio '$DOMAIN_NAME' no encontrado en Linode (¿token inválido?)."
  exit 1
fi

EXISTING_RECORD="$(linode_api GET "/domains/$DOMAIN_ID/records?page_size=500" \
  | jq -r --arg n "$SUBDOMAIN" '.data[]? | select(.type=="A" and .name==$n) | .id' | head -n1 || true)"

if [ -n "$EXISTING_RECORD" ]; then
  echo "ℹ️ El registro A '$SUBDOMAIN.$DOMAIN_NAME' ya existe. Se omite su creación."
else
  echo "🌐 Creando subdominio '$SITE_NAME' → $SERVER_IP..."
  BODY="$(jq -n --arg n "$SUBDOMAIN" --arg ip "$SERVER_IP" '{type:"A", name:$n, target:$ip, ttl_sec:300}')"
  RESPONSE="$(linode_api POST "/domains/$DOMAIN_ID/records" "$BODY")"
  if echo "$RESPONSE" | jq -e '.errors' >/dev/null; then
    echo "❌ Error al crear subdominio:"
    echo "$RESPONSE" | jq '.errors'
    exit 1
  fi
  echo "✅ Subdominio '$SITE_NAME' creado."
fi

# ======================
# 🏗️ Crear sitio ERPNext
# ======================
cd "$BENCH_PATH"

echo "🌐 Creando sitio ERPNext: $SITE_NAME"
# Sin --mariadb-user-host-login-scope="%": la BD es local, el usuario del sitio solo necesita 'localhost'.
as_frappe bench new-site "$SITE_NAME" \
  --admin-password "$ADMIN_PASSWORD" \
  --mariadb-root-username "$DB_USER" \
  --mariadb-root-password "$DB_PASSWORD"

if [ "$ADMIN_GENERATED" = true ]; then
  set_env "$ADMIN_KEY" "$ADMIN_PASSWORD"
fi

echo "📦 Instalando apps..."
for app in $SITE_APPS; do
  as_frappe bench --site "$SITE_NAME" install-app "$app"
done

# ======================
# 🔐 Permisos y nginx
# ======================
echo "🔐 Ajustando permisos..."
sudo chmod o+x "$FRAPPE_HOME" "$BENCH_PATH" "$BENCH_PATH/sites" "$BENCH_PATH/sites/$SITE_NAME"
sudo chmod -R o+rx "$BENCH_PATH/sites/$SITE_NAME/public"

# Con dns_multitenant hay que regenerar nginx para publicar el sitio nuevo.
if [ -L "/etc/nginx/conf.d/$BENCH_NAME.conf" ] || [ -f "/etc/nginx/conf.d/$BENCH_NAME.conf" ]; then
  echo "🔁 Regenerando nginx y recargando..."
  as_frappe bench setup nginx --yes
  sudo nginx -t
  sudo systemctl reload nginx
else
  echo "ℹ️ Producción aún no configurada (scripts/02-bench-setup/03-setup-production.sh): se omite nginx."
fi

echo "✅ Sitio '$SITE_NAME' creado, apps instaladas y subdominio configurado correctamente."
if [ "$ADMIN_GENERATED" = true ]; then
  echo "🔑 Contraseña de Administrator guardada en $ENV_FILE como $ADMIN_KEY"
  echo "   Consúltala con: sudo grep $ADMIN_KEY $ENV_FILE"
fi
echo "➡️  Cuando el DNS propague, activa SSL: bash scripts/sites/enable-ssl.sh $SITE_NAME <correo>"
