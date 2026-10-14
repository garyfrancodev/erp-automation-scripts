#!/bin/bash
source "$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)/core/lib.sh"

# Uso: bash create-site.sh <subdominio> [db-user db-password]
#   - db-user / db-password son opcionales: por defecto se leen de .env (DB_ROOT_USER / DB_ROOT_PASSWORD).
#   - ADMIN_PASSWORD (variable de entorno) es opcional: si no se indica se genera una aleatoria.
FORCE=false
POSITIONAL_ARGS=()

for arg in "$@"; do
  case "$arg" in
    --force|-f)
      FORCE=true
      ;;
    *)
      POSITIONAL_ARGS+=("$arg")
      ;;
  esac
done

INPUT_NAME="${POSITIONAL_ARGS[0]:-}"

if [ -z "$INPUT_NAME" ]; then
  echo "❌ Uso: bash $(basename "$0") <dominio-o-subdominio> [db-user db-password] [--force]"
  echo "   Ejemplos:"
  echo "     erp site create francosystem.com"
  echo "     erp site create francosystem.com --force"
  echo "     erp site create garyfranco.dev"
  echo "     erp site create cliente1                   (usará cliente1.$DOMAIN_NAME)"
  exit 1
fi

load_env
DB_USER="${POSITIONAL_ARGS[1]:-${DB_ROOT_USER:-}}"
DB_PASSWORD="${POSITIONAL_ARGS[2]:-${DB_ROOT_PASSWORD:-}}"
if [ -z "$DB_USER" ] || [ -z "$DB_PASSWORD" ]; then
  echo "❌ No hay credenciales de MariaDB. Ejecuta install-mariadb.sh o pásalas como 2º y 3er argumento."
  exit 1
fi

if [[ "$INPUT_NAME" == *"."* ]]; then
  # Dominio completo especificado (ej. francosystem.com o garyfranco.dev)
  SITE_NAME="$INPUT_NAME"
  SUBDOMAIN="${INPUT_NAME%%.*}"
else
  # Subdominio simple (ej. cliente1 -> cliente1.mandox.com.bo)
  SUBDOMAIN="$INPUT_NAME"
  SITE_NAME="$SUBDOMAIN.$DOMAIN_NAME"
fi

ADMIN_KEY="ADMIN_PASSWORD_${SITE_NAME^^}"
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
  if [ "$FORCE" = true ]; then
    echo "⚠️  Eliminando sitio existente '$SITE_NAME' (--force activado)..."
    (cd "$BENCH_PATH" && as_frappe bench drop-site "$SITE_NAME" --force --root-password "$DB_PASSWORD") 2>/dev/null || true
    sudo rm -rf "$BENCH_PATH/sites/$SITE_NAME"
    echo "✅ Sitio anterior '$SITE_NAME' eliminado para instalación limpia."
  else
    echo "⚠️ El sitio '$SITE_NAME' ya existe (o una instalación anterior quedó a medias)."
    echo "   Para reinstalarlo limpiamente desde cero, ejecuta:"
    echo "   erp site create $SITE_NAME --force"
    exit 1
  fi
fi



# ======================
# 🌐 Configuración DNS (Linode opcional)
# ======================
MANAGE_LINODE_DNS=false
if [ -n "${ERP_DOMAINS_API:-}" ]; then
  MANAGE_LINODE_DNS=true
elif command -v op &>/dev/null; then
  ERP_DOMAINS_API="$(op read "$OP_DOMAINS_REF" 2>/dev/null || true)"
  [ -n "$ERP_DOMAINS_API" ] && MANAGE_LINODE_DNS=true
fi

if [ "$MANAGE_LINODE_DNS" = true ]; then
  linode_api() {
    local method="$1" path="$2" body="${3:-}"
    local args=(-sS -X "$method" -K <(printf 'header = "Authorization: Bearer %s"\n' "$ERP_DOMAINS_API"))
    if [ -n "$body" ]; then
      args+=(-H "Content-Type: application/json" -d "$body")
    fi
    curl "${args[@]}" "https://api.linode.com/v4$path"
  }

  DOMAIN_ID="$(linode_api GET "/domains?page_size=500" \
    | jq -r --arg d "$DOMAIN_NAME" '.data[]? | select(.domain==$d) | .id' 2>/dev/null || true)"

  if [ -n "$DOMAIN_ID" ] && [[ "$SITE_NAME" == *"$DOMAIN_NAME"* ]]; then
    EXISTING_RECORD="$(linode_api GET "/domains/$DOMAIN_ID/records?page_size=500" \
      | jq -r --arg n "$SUBDOMAIN" '.data[]? | select(.type=="A" and .name==$n) | .id' | head -n1 || true)"

    if [ -n "$EXISTING_RECORD" ]; then
      echo "ℹ️ El registro A '$SUBDOMAIN.$DOMAIN_NAME' ya existe en Linode."
    else
      echo "🌐 Creando subdominio en Linode: '$SITE_NAME' → $SERVER_IP..."
      BODY="$(jq -n --arg n "$SUBDOMAIN" --arg ip "$SERVER_IP" '{type:"A", name:$n, target:$ip, ttl_sec:300}')"
      linode_api POST "/domains/$DOMAIN_ID/records" "$BODY" >/dev/null || true
      echo "✅ Subdominio '$SITE_NAME' registrado en Linode."
    fi
  else
    echo "ℹ️ Dominio no perteneciente a Linode DNS. Asegúrate de configurar el registro A:"
    echo "   $SITE_NAME → $SERVER_IP (en DigitalOcean, Cloudflare o tu proveedor DNS)"
  fi
else
  echo "ℹ️ Asegúrate de apuntar tu registro A hacia la IP de este servidor:"
  echo "   $SITE_NAME  A  $SERVER_IP"
fi

# ======================
# 🏗️ Crear sitio ERPNext
# ======================
# Garantizar que Supervisor y Redis Queue estén activos para que 'install-app' no falle
ensure_redis_and_supervisor

cd "$BENCH_PATH"

echo "🌐 Creando sitio ERPNext: $SITE_NAME"
# Sin --mariadb-user-host-login-scope="%": la BD es local, el usuario del sitio solo necesita 'localhost'.
as_frappe bench new-site "$SITE_NAME" \
  --admin-password "$ADMIN_PASSWORD" \
  --mariadb-root-username "$DB_USER" \
  --mariadb-root-password "$DB_PASSWORD" \
  --force


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
