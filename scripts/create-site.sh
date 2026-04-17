#!/bin/bash
#
# create-site.sh - Crea un sitio ERPNext completo (DNS + sitio + apps + Nginx)
# Requisitos: ejecutar como 'frappe'
# Uso: ./create-site.sh <subdominio> [app1 app2 ...]
# Ejemplo: ./create-site.sh tic erpnext payments hrms
#

set -euo pipefail

# ----------------------------------------------------------------------
# Configuración
# ----------------------------------------------------------------------
FRAPPE_USER="frappe"
BENCH_DIR="/home/${FRAPPE_USER}/frappe-bench"
ENV_FILE="/etc/frappe-automation/.env"

# Variables esperadas en .env:
#   MYSQL_ROOT_PASSWORD=xxx
#   DOMAIN_NAME=wdstudio.com.bo
#   SERVER_IP=172.235.x.x
#   LINODE_API_TOKEN=xxx

# ----------------------------------------------------------------------
# Parsear argumentos
# ----------------------------------------------------------------------

if [[ $# -lt 1 ]]; then
    cat <<EOF
Uso: $0 <subdominio> [apps...]

Argumentos:
  subdominio    Nombre del subdominio (ej. 'tic' para tic.wdstudio.com.bo)
                Usa '@' o 'root' para el dominio raíz
  apps          Apps a instalar (opcional)

Ejemplos:
  $0 tic erpnext payments hrms
  $0 logisstar erpnext payments webshop
  $0 ingetrans erpnext
  $0 @ erpnext payments
EOF
    exit 1
fi

SUBDOMAIN="$1"
shift
APPS_TO_INSTALL=("$@")

# ----------------------------------------------------------------------
# Validaciones iniciales
# ----------------------------------------------------------------------

echo "🔍 [1/9] Validando entorno..."

if [[ "$(whoami)" != "${FRAPPE_USER}" ]]; then
    echo "❌ Ejecutar como '${FRAPPE_USER}'." >&2
    exit 1
fi

# Validar dependencias
for cmd in jq curl bench dig openssl; do
    if ! command -v "${cmd}" &> /dev/null; then
        echo "❌ Falta '${cmd}'. Instálalo antes de continuar." >&2
        exit 1
    fi
done

# Validar que existe el .env
if [[ ! -f "${ENV_FILE}" ]]; then
    echo "❌ No existe ${ENV_FILE}." >&2
    exit 1
fi

# Leer config del .env
DOMAIN_NAME=$(sudo grep "^DOMAIN_NAME=" "${ENV_FILE}" | cut -d= -f2- || echo "")
SERVER_IP=$(sudo grep "^SERVER_IP=" "${ENV_FILE}" | cut -d= -f2- || echo "")
MYSQL_ROOT_PASSWORD=$(sudo grep "^MYSQL_ROOT_PASSWORD=" "${ENV_FILE}" | cut -d= -f2- || echo "")
LINODE_API_TOKEN=$(sudo grep "^LINODE_API_TOKEN=" "${ENV_FILE}" | cut -d= -f2- || echo "")

# Validar variables
MISSING_VARS=()
[[ -z "${DOMAIN_NAME}" ]] && MISSING_VARS+=("DOMAIN_NAME")
[[ -z "${SERVER_IP}" ]] && MISSING_VARS+=("SERVER_IP")
[[ -z "${MYSQL_ROOT_PASSWORD}" ]] && MISSING_VARS+=("MYSQL_ROOT_PASSWORD")
[[ -z "${LINODE_API_TOKEN}" ]] && MISSING_VARS+=("LINODE_API_TOKEN")

if [[ ${#MISSING_VARS[@]} -gt 0 ]]; then
    echo "❌ Variables faltantes en ${ENV_FILE}: ${MISSING_VARS[*]}" >&2
    exit 1
fi

# ----------------------------------------------------------------------
# Normalizar y validar subdominio
# ----------------------------------------------------------------------

if [[ "${SUBDOMAIN}" == "@" ]] || [[ "${SUBDOMAIN}" == "root" ]]; then
    SITE_NAME="${DOMAIN_NAME}"
    DNS_NAME=""   # Registro raíz en Linode
    DISPLAY_DNS_NAME="@"
else
    if ! [[ "${SUBDOMAIN}" =~ ^[a-z0-9]([a-z0-9-]*[a-z0-9])?$ ]]; then
        echo "❌ Subdominio inválido: '${SUBDOMAIN}'" >&2
        echo "   Debe contener solo letras minúsculas, números y guiones" >&2
        exit 1
    fi

    SITE_NAME="${SUBDOMAIN}.${DOMAIN_NAME}"
    DNS_NAME="${SUBDOMAIN}"
    DISPLAY_DNS_NAME="${SUBDOMAIN}"
fi

# Validar que el bench existe
if [[ ! -d "${BENCH_DIR}" ]]; then
    echo "❌ No existe ${BENCH_DIR}." >&2
    exit 1
fi

cd "${BENCH_DIR}"

# Validar que el sitio NO existe
if [[ -d "sites/${SITE_NAME}" ]]; then
    echo "❌ El sitio '${SITE_NAME}' ya existe en ${BENCH_DIR}/sites/" >&2
    echo "   Para recrearlo:" >&2
    echo "     bench drop-site ${SITE_NAME} --root-password <pass> --no-backup" >&2
    exit 1
fi

# Validar que las apps están descargadas
for APP in "${APPS_TO_INSTALL[@]}"; do
    if [[ ! -d "apps/${APP}" ]]; then
        echo "❌ App '${APP}' no descargada. Corre download-apps.sh primero." >&2
        exit 1
    fi
done

# Validar token de Linode
if ! curl -fsS -H "Authorization: Bearer ${LINODE_API_TOKEN}" \
    "https://api.linode.com/v4/domains?page_size=1" > /dev/null; then
    echo "❌ Token de Linode inválido o sin acceso a Domains API." >&2
    exit 1
fi

echo "   ✅ Todas las validaciones pasaron"
echo "   📋 Sitio:     ${SITE_NAME}"
echo "   📋 DNS:       ${DISPLAY_DNS_NAME}"
echo "   📋 IP:        ${SERVER_IP}"
echo "   📋 Apps:      ${APPS_TO_INSTALL[*]:-'(solo frappe)'}"

# ----------------------------------------------------------------------
# Log
# ----------------------------------------------------------------------
LOG_FILE="/home/${FRAPPE_USER}/logs/create-site-$(echo "${SITE_NAME}" | tr '.' '_')-$(date +%Y%m%d-%H%M%S).log"
mkdir -p "$(dirname "${LOG_FILE}")"
exec > >(tee -a "${LOG_FILE}") 2>&1

echo "📝 Log: ${LOG_FILE}"
echo "🕐 Inicio: $(date)"

# ----------------------------------------------------------------------
# 2. Verificar/crear registro DNS en Linode
# ----------------------------------------------------------------------

echo "🌐 [2/9] Configurando DNS en Linode..."

# Obtener domain_id
DOMAIN_ID=$(curl -sS -H "Authorization: Bearer ${LINODE_API_TOKEN}" \
    "https://api.linode.com/v4/domains?page_size=500" \
    | jq -r ".data[] | select(.domain==\"${DOMAIN_NAME}\") | .id")

if [[ -z "${DOMAIN_ID}" ]]; then
    echo "❌ Dominio '${DOMAIN_NAME}' no encontrado en Linode." >&2
    exit 1
fi

echo "   ✅ Dominio encontrado (ID: ${DOMAIN_ID})"

# Verificar si el registro A ya existe (idempotencia)
EXISTING_RECORD=$(curl -sS -H "Authorization: Bearer ${LINODE_API_TOKEN}" \
    "https://api.linode.com/v4/domains/${DOMAIN_ID}/records?page_size=500" \
    | jq -r ".data[] | select(.type==\"A\" and .name==\"${DNS_NAME}\") | .id")

if [[ -n "${EXISTING_RECORD}" ]]; then
    echo "   ℹ️  Registro A '${DISPLAY_DNS_NAME}' ya existe (ID: ${EXISTING_RECORD})"

    CURRENT_TARGET=$(curl -sS -H "Authorization: Bearer ${LINODE_API_TOKEN}" \
        "https://api.linode.com/v4/domains/${DOMAIN_ID}/records/${EXISTING_RECORD}" \
        | jq -r '.target')

    if [[ "${CURRENT_TARGET}" != "${SERVER_IP}" ]]; then
        echo "   ⚠️  Apunta a ${CURRENT_TARGET}, actualizando a ${SERVER_IP}..."
        curl -sS -X PUT \
            -H "Authorization: Bearer ${LINODE_API_TOKEN}" \
            -H "Content-Type: application/json" \
            -d "{\"target\": \"${SERVER_IP}\"}" \
            "https://api.linode.com/v4/domains/${DOMAIN_ID}/records/${EXISTING_RECORD}" > /dev/null
        echo "   ✅ Registro actualizado"
    else
        echo "   ✅ Ya apunta a la IP correcta"
    fi
else
    echo "   📝 Creando registro A '${DISPLAY_DNS_NAME}' → ${SERVER_IP}..."

    CREATE_RESPONSE=$(curl -sS -X POST \
        -H "Authorization: Bearer ${LINODE_API_TOKEN}" \
        -H "Content-Type: application/json" \
        -d "{
            \"type\": \"A\",
            \"name\": \"${DNS_NAME}\",
            \"target\": \"${SERVER_IP}\",
            \"ttl_sec\": 300
        }" \
        "https://api.linode.com/v4/domains/${DOMAIN_ID}/records")

    if echo "${CREATE_RESPONSE}" | jq -e '.errors' > /dev/null; then
        echo "   ❌ Error al crear registro DNS:" >&2
        echo "${CREATE_RESPONSE}" | jq '.errors' >&2
        exit 1
    fi

    echo "   ✅ Registro creado"
fi

# ----------------------------------------------------------------------
# 3. Generar password del Administrator
# ----------------------------------------------------------------------

echo "🔐 [3/9] Generando password del Administrator..."

ADMIN_PASSWORD=$(openssl rand -base64 32 | tr -d '/+=' | cut -c1-24)

SITE_KEY=$(echo "${SITE_NAME}" | tr '.' '_' | tr '[:lower:]' '[:upper:]')
ADMIN_KEY="SITE_${SITE_KEY}_ADMIN_PASSWORD"

sudo sed -i "/^${ADMIN_KEY}=/d" "${ENV_FILE}"
echo "${ADMIN_KEY}=${ADMIN_PASSWORD}" | sudo tee -a "${ENV_FILE}" > /dev/null
sudo chmod 600 "${ENV_FILE}"

echo "   ✅ Password guardado en ${ENV_FILE} como ${ADMIN_KEY}"

# ----------------------------------------------------------------------
# 4. Crear sitio
# ----------------------------------------------------------------------

echo "🏗️  [4/9] Creando sitio ${SITE_NAME}..."

bench new-site "${SITE_NAME}" \
    --mariadb-root-username root \
    --mariadb-root-password "${MYSQL_ROOT_PASSWORD}" \
    --admin-password "${ADMIN_PASSWORD}" \
    --db-type mariadb \
    --mariadb-user-host-login-scope localhost \
    --verbose

echo "   ✅ Sitio creado"

# ----------------------------------------------------------------------
# 5. Instalar apps
# ----------------------------------------------------------------------

if [[ ${#APPS_TO_INSTALL[@]} -gt 0 ]]; then
    echo "📥 [5/9] Instalando apps..."

    for APP in "${APPS_TO_INSTALL[@]}"; do
        echo ""
        echo "   📦 Instalando ${APP}..."
        if bench --site "${SITE_NAME}" install-app "${APP}"; then
            echo "   ✅ ${APP} instalado"
        else
            echo "   ❌ Falló instalación de ${APP}" >&2
            echo "   Reintentar manualmente: bench --site ${SITE_NAME} install-app ${APP}" >&2
            exit 1
        fi
    done
else
    echo "⏭️  [5/9] Sin apps para instalar"
fi

# ----------------------------------------------------------------------
# 6. Configurar sitio
# ----------------------------------------------------------------------

echo "⚙️  [6/9] Configurando sitio..."

bench --site "${SITE_NAME}" enable-scheduler
bench --site "${SITE_NAME}" set-maintenance-mode off

echo "   ✅ Scheduler habilitado"

# ----------------------------------------------------------------------
# 7. Ajustar permisos
# ----------------------------------------------------------------------

echo "🔐 [7/9] Ajustando permisos para Nginx..."

chmod o+rx \
    "/home/${FRAPPE_USER}" \
    "${BENCH_DIR}" \
    "${BENCH_DIR}/sites"

chmod -R o+rX "${BENCH_DIR}/sites/${SITE_NAME}/public" 2>/dev/null || true

echo "   ✅ Permisos configurados"

# ----------------------------------------------------------------------
# 8. Regenerar config de Nginx
# ----------------------------------------------------------------------

echo "🌐 [8/9] Actualizando Nginx..."

bench setup nginx --yes

if ! sudo nginx -t > /dev/null 2>&1; then
    echo "❌ Error en config de Nginx:" >&2
    sudo nginx -t >&2
    exit 1
fi

sudo systemctl reload nginx
echo "   ✅ Nginx recargado"

# ----------------------------------------------------------------------
# 9. Verificar propagación DNS
# ----------------------------------------------------------------------

echo "🔎 [9/9] Verificando conectividad..."

echo "   ⏳ Esperando propagación DNS (hasta 30s)..."
DNS_OK=false
for i in {1..6}; do
    RESOLVED_IP=$(dig +short "${SITE_NAME}" @8.8.8.8 2>/dev/null | tail -n1)
    if [[ "${RESOLVED_IP}" == "${SERVER_IP}" ]]; then
        echo "   ✅ DNS propagado: ${SITE_NAME} → ${RESOLVED_IP}"
        DNS_OK=true
        break
    fi
    if [[ $i -lt 6 ]]; then
        sleep 5
    fi
done

if [[ "${DNS_OK}" == "false" ]]; then
    echo "   ⚠️  DNS aún no propagado. Verifica manualmente en unos minutos:"
    echo "      dig ${SITE_NAME}"
fi

# Test HTTP
HTTP_STATUS=$(curl -sS -o /dev/null -w "%{http_code}" --max-time 10 \
    -H "Host: ${SITE_NAME}" \
    "http://${SERVER_IP}" 2>/dev/null || echo "000")

if [[ "${HTTP_STATUS}" =~ ^[23] ]]; then
    echo "   ✅ Sitio responde (HTTP ${HTTP_STATUS})"
else
    echo "   ℹ️  HTTP status: ${HTTP_STATUS} (normal si aún no hay SSL)"
fi

# ----------------------------------------------------------------------
# Resumen final
# ----------------------------------------------------------------------

echo ""
echo "━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━"
echo "✅ Sitio ${SITE_NAME} listo"
echo "━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━"
echo "  URL:              http://${SITE_NAME}"
echo "  Apps:             ${APPS_TO_INSTALL[*]:-'(solo frappe)'}"
echo "  Admin user:       Administrator"
echo "  Admin password:   en ${ENV_FILE} como ${ADMIN_KEY}"
echo "  DNS record:       ${DISPLAY_DNS_NAME}.${DOMAIN_NAME} → ${SERVER_IP}"
echo "━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━"
echo ""
echo "🕐 Fin: $(date)"
echo ""
echo "ℹ️  Próximo paso — configurar SSL:"
echo "   sudo certbot --nginx -d ${SITE_NAME}"
