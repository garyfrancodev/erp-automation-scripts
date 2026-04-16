#!/bin/bash
#
# enable-ssl.sh - Habilita SSL con Let's Encrypt para un sitio de Frappe
# Requisitos: ejecutar como 'frappe', sitio ya creado y DNS propagado
# Uso: ./enable-ssl.sh <subdominio> [email]
# Ejemplo: ./enable-ssl.sh tic
#         ./enable-ssl.sh tic admin@wdstudio.com.bo
#

set -euo pipefail

# ----------------------------------------------------------------------
# Configuración
# ----------------------------------------------------------------------
FRAPPE_USER="frappe"
BENCH_DIR="/home/${FRAPPE_USER}/frappe-bench"
ENV_FILE="/etc/frappe-automation/.env"

# ----------------------------------------------------------------------
# Parsear argumentos
# ----------------------------------------------------------------------

if [[ $# -lt 1 ]]; then
    cat <<EOF
Uso: $0 <subdominio> [email]

Argumentos:
  subdominio    Nombre del subdominio (ej. 'tic' para tic.wdstudio.com.bo)
  email         Email para Let's Encrypt (opcional, usa LETSENCRYPT_EMAIL del .env)

Ejemplos:
  $0 tic
  $0 logisstar admin@wdstudio.com.bo
  $0 ingetrans --staging        # Modo de prueba (no cuenta contra rate limits)

Flags:
  --staging     Usa el servidor de pruebas de Let's Encrypt (para testing)
  --force       Fuerza renovación incluso si el cert ya existe
EOF
    exit 1
fi

SUBDOMAIN="$1"
shift

# Parsear flags opcionales
EMAIL=""
STAGING=false
FORCE=false

while [[ $# -gt 0 ]]; do
    case "$1" in
        --staging)
            STAGING=true
            shift
            ;;
        --force)
            FORCE=true
            shift
            ;;
        --*)
            echo "❌ Flag desconocido: $1" >&2
            exit 1
            ;;
        *)
            EMAIL="$1"
            shift
            ;;
    esac
done

# ----------------------------------------------------------------------
# Validaciones iniciales
# ----------------------------------------------------------------------

echo "🔍 [1/7] Validando entorno..."

if [[ "$(whoami)" != "${FRAPPE_USER}" ]]; then
    echo "❌ Ejecutar como '${FRAPPE_USER}'." >&2
    exit 1
fi

# Validar formato del subdominio
if ! [[ "${SUBDOMAIN}" =~ ^[a-z0-9]([a-z0-9-]*[a-z0-9])?$ ]]; then
    echo "❌ Subdominio inválido: '${SUBDOMAIN}'" >&2
    exit 1
fi

# Validar dependencias
for cmd in bench certbot curl dig; do
    if ! command -v "${cmd}" &> /dev/null; then
        echo "❌ Falta '${cmd}'." >&2
        [[ "${cmd}" == "certbot" ]] && echo "   sudo apt install certbot python3-certbot-nginx" >&2
        exit 1
    fi
done

# Validar .env
if [[ ! -f "${ENV_FILE}" ]]; then
    echo "❌ No existe ${ENV_FILE}." >&2
    exit 1
fi

# Leer config del .env
DOMAIN_NAME=$(grep "^DOMAIN_NAME=" "${ENV_FILE}" | cut -d= -f2- || echo "")
SERVER_IP=$(grep "^SERVER_IP=" "${ENV_FILE}" | cut -d= -f2- || echo "")

# Email: parámetro > .env > error
if [[ -z "${EMAIL}" ]]; then
    EMAIL=$(grep "^LETSENCRYPT_EMAIL=" "${ENV_FILE}" | cut -d= -f2- || echo "")
fi

MISSING=()
[[ -z "${DOMAIN_NAME}" ]] && MISSING+=("DOMAIN_NAME")
[[ -z "${SERVER_IP}" ]] && MISSING+=("SERVER_IP")
[[ -z "${EMAIL}" ]] && MISSING+=("LETSENCRYPT_EMAIL o parámetro")

if [[ ${#MISSING[@]} -gt 0 ]]; then
    echo "❌ Faltan: ${MISSING[*]}" >&2
    exit 1
fi

# Validar formato de email básico
if ! [[ "${EMAIL}" =~ ^[A-Za-z0-9._%+-]+@[A-Za-z0-9.-]+\.[A-Za-z]{2,}$ ]]; then
    echo "❌ Email inválido: ${EMAIL}" >&2
    exit 1
fi

SITE_NAME="${SUBDOMAIN}.${DOMAIN_NAME}"
SITE_PATH="${BENCH_DIR}/sites/${SITE_NAME}"

# Validar que el sitio existe
if [[ ! -d "${SITE_PATH}" ]]; then
    echo "❌ El sitio '${SITE_NAME}' no existe en ${SITE_PATH}" >&2
    echo "   Créalo primero con: ./create-site.sh ${SUBDOMAIN} <apps>" >&2
    exit 1
fi

echo "   ✅ Validaciones OK"
echo "   📋 Sitio:     ${SITE_NAME}"
echo "   📋 Email:     ${EMAIL}"
echo "   📋 Staging:   ${STAGING}"

# ----------------------------------------------------------------------
# Log
# ----------------------------------------------------------------------
LOG_FILE="/home/${FRAPPE_USER}/logs/enable-ssl-${SUBDOMAIN}-$(date +%Y%m%d-%H%M%S).log"
mkdir -p "$(dirname "${LOG_FILE}")"
exec > >(tee -a "${LOG_FILE}") 2>&1

echo "📝 Log: ${LOG_FILE}"
echo "🕐 Inicio: $(date)"

# ----------------------------------------------------------------------
# 2. Verificar propagación DNS
# ----------------------------------------------------------------------

echo "🌐 [2/7] Verificando propagación DNS..."

RESOLVED_IP=$(dig +short "${SITE_NAME}" @8.8.8.8 2>/dev/null | tail -n1)

if [[ -z "${RESOLVED_IP}" ]]; then
    echo "❌ ${SITE_NAME} no resuelve en DNS." >&2
    echo "   Verifica el registro A en Linode y espera propagación (hasta 5min)." >&2
    exit 1
fi

if [[ "${RESOLVED_IP}" != "${SERVER_IP}" ]]; then
    echo "❌ DNS desincronizado:" >&2
    echo "   ${SITE_NAME} resuelve a: ${RESOLVED_IP}" >&2
    echo "   Este servidor es:        ${SERVER_IP}" >&2
    echo "   Corrige el registro DNS antes de continuar." >&2
    exit 1
fi

echo "   ✅ DNS OK: ${SITE_NAME} → ${RESOLVED_IP}"

# ----------------------------------------------------------------------
# 3. Verificar accesibilidad HTTP (Let's Encrypt necesita puerto 80)
# ----------------------------------------------------------------------

echo "🔌 [3/7] Verificando accesibilidad HTTP..."

HTTP_STATUS=$(curl -sS -o /dev/null -w "%{http_code}" --max-time 10 \
    "http://${SITE_NAME}" 2>/dev/null || echo "000")

if [[ "${HTTP_STATUS}" == "000" ]]; then
    echo "❌ ${SITE_NAME} no responde en HTTP (puerto 80)." >&2
    echo "   Posibles causas:" >&2
    echo "   - Firewall bloqueando puerto 80 (sudo ufw status)" >&2
    echo "   - Nginx no corriendo (sudo systemctl status nginx)" >&2
    echo "   - DNS aún no propagado globalmente" >&2
    exit 1
fi

# Cualquier 2xx, 3xx o 4xx indica que al menos llega a Nginx
if [[ "${HTTP_STATUS}" =~ ^[234] ]]; then
    echo "   ✅ HTTP responde (status: ${HTTP_STATUS})"
else
    echo "   ⚠️  HTTP status inesperado: ${HTTP_STATUS}" >&2
    echo "   Continuando de todos modos..."
fi

# ----------------------------------------------------------------------
# 4. Verificar si ya existe certificado
# ----------------------------------------------------------------------

echo "🔍 [4/7] Verificando certificados existentes..."

CERT_PATH="/etc/letsencrypt/live/${SITE_NAME}"

if sudo test -d "${CERT_PATH}" && [[ "${FORCE}" == "false" ]]; then
    # Obtener fecha de expiración
    EXPIRY=$(sudo openssl x509 -enddate -noout -in "${CERT_PATH}/cert.pem" 2>/dev/null | cut -d= -f2 || echo "unknown")
    EXPIRY_EPOCH=$(date -d "${EXPIRY}" +%s 2>/dev/null || echo "0")
    NOW_EPOCH=$(date +%s)
    DAYS_LEFT=$(( (EXPIRY_EPOCH - NOW_EPOCH) / 86400 ))

    echo "   ℹ️  Certificado ya existe"
    echo "   📅 Expira: ${EXPIRY} (${DAYS_LEFT} días)"

    if [[ ${DAYS_LEFT} -gt 30 ]]; then
        echo "   ✅ Cert vigente por más de 30 días, no se renueva"
        echo "   Para forzar renovación: $0 ${SUBDOMAIN} --force"
        exit 0
    else
        echo "   ⚠️  Cert expira en ${DAYS_LEFT} días, renovando..."
    fi
fi

# ----------------------------------------------------------------------
# 5. Emitir certificado con certbot --nginx (no detiene servicio)
# ----------------------------------------------------------------------

echo "🔒 [5/7] Emitiendo certificado SSL..."

CERTBOT_ARGS=(
    "--nginx"
    "-d" "${SITE_NAME}"
    "--non-interactive"
    "--agree-tos"
    "--email" "${EMAIL}"
    "--redirect"                          # Redirige HTTP → HTTPS automáticamente
    "--no-eff-email"                      # No se registra en EFF mailing list
    "--expand"                            # Expande cert existente si es necesario
)

if [[ "${STAGING}" == "true" ]]; then
    CERTBOT_ARGS+=("--staging")
    echo "   ⚠️  MODO STAGING (cert no válido para browsers, solo testing)"
fi

if [[ "${FORCE}" == "true" ]]; then
    CERTBOT_ARGS+=("--force-renewal")
fi

echo "   📡 Ejecutando: sudo certbot ${CERTBOT_ARGS[*]}"

if sudo certbot "${CERTBOT_ARGS[@]}"; then
    echo "   ✅ Certificado emitido correctamente"
else
    echo "❌ Error al emitir certificado." >&2
    echo "   Revisa: /var/log/letsencrypt/letsencrypt.log" >&2
    exit 1
fi

# ----------------------------------------------------------------------
# 6. Verificar renovación automática
# ----------------------------------------------------------------------

echo "🔄 [6/7] Verificando renovación automática..."

# Certbot instala automáticamente un timer de systemd para renovación
if systemctl list-timers 2>/dev/null | grep -q certbot; then
    echo "   ✅ Timer de renovación activo"

    # Probar que la renovación funcionaría (dry-run)
    if sudo certbot renew --dry-run --cert-name "${SITE_NAME}" > /dev/null 2>&1; then
        echo "   ✅ Dry-run de renovación: OK"
    else
        echo "   ⚠️  Dry-run de renovación falló (revisa logs)"
    fi
else
    echo "   ⚠️  Timer de certbot no encontrado. Activando..."
    sudo systemctl enable --now certbot.timer
fi

# ----------------------------------------------------------------------
# 7. Verificar HTTPS funcional
# ----------------------------------------------------------------------

echo "🔎 [7/7] Verificando HTTPS..."

# Esperar unos segundos para que nginx reload tome efecto
sleep 3

HTTPS_STATUS=$(curl -sS -o /dev/null -w "%{http_code}" --max-time 10 \
    "https://${SITE_NAME}" 2>/dev/null || echo "000")

if [[ "${HTTPS_STATUS}" =~ ^[234] ]]; then
    echo "   ✅ HTTPS responde (status: ${HTTPS_STATUS})"
else
    echo "   ⚠️  HTTPS status: ${HTTPS_STATUS}"
    echo "   Revisa: sudo nginx -t && sudo systemctl status nginx"
fi

# Verificar redirect HTTP → HTTPS
REDIRECT_STATUS=$(curl -sS -o /dev/null -w "%{http_code}" --max-time 10 \
    "http://${SITE_NAME}" 2>/dev/null || echo "000")

if [[ "${REDIRECT_STATUS}" =~ ^30 ]]; then
    echo "   ✅ Redirect HTTP → HTTPS activo (status: ${REDIRECT_STATUS})"
else
    echo "   ℹ️  Redirect status: ${REDIRECT_STATUS}"
fi

# ----------------------------------------------------------------------
# Resumen final
# ----------------------------------------------------------------------

CERT_EXPIRY=$(sudo openssl x509 -enddate -noout -in "/etc/letsencrypt/live/${SITE_NAME}/cert.pem" 2>/dev/null | cut -d= -f2 || echo "unknown")

echo ""
echo "━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━"
echo "✅ SSL habilitado para ${SITE_NAME}"
echo "━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━"
echo "  URL HTTPS:       https://${SITE_NAME}"
echo "  Email:           ${EMAIL}"
echo "  Cert:            /etc/letsencrypt/live/${SITE_NAME}/"
echo "  Expira:          ${CERT_EXPIRY}"
echo "  Renovación:      automática (certbot.timer)"
echo "  Redirect:        HTTP → HTTPS"
if [[ "${STAGING}" == "true" ]]; then
    echo "  ⚠️  MODO STAGING (repite sin --staging para cert real)"
fi
echo "━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━"
echo ""
echo "🕐 Fin: $(date)"
