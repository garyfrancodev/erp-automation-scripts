#!/bin/bash
#
# download-apps.sh - Descarga las apps de Frappe al bench (NO las instala en sitios)
# Requisitos: ejecutar como usuario 'frappe', con bench ya inicializado
#

set -euo pipefail

# ----------------------------------------------------------------------
# Configuración
# ----------------------------------------------------------------------
FRAPPE_USER="frappe"
BENCH_DIR="/home/${FRAPPE_USER}/frappe-bench"
FRAPPE_BRANCH="version-15"

# Apps a descargar en orden de dependencia
# Formato: "app_name|repo_url"
# - Si el repo está en github.com/frappe/<app>, no necesitas URL (bench lo resuelve)
# - Para apps de terceros, pon la URL completa
APPS=(
    "erpnext|https://github.com/frappe/erpnext"
    "payments|https://github.com/frappe/payments"
    "hrms|https://github.com/frappe/hrms"
    "webshop|https://github.com/frappe/webshop"
)

# ----------------------------------------------------------------------
# Validaciones
# ----------------------------------------------------------------------

echo "🔍 [1/4] Validando entorno..."

if [[ "$(whoami)" != "${FRAPPE_USER}" ]]; then
    echo "❌ Este script debe ejecutarse como '${FRAPPE_USER}'." >&2
    exit 1
fi

if [[ $EUID -eq 0 ]]; then
    echo "❌ No ejecutar como root." >&2
    exit 1
fi

if ! command -v bench &> /dev/null; then
    echo "❌ 'bench' no está disponible. Corre install-frappe.sh primero." >&2
    exit 1
fi

if [[ ! -d "${BENCH_DIR}" ]]; then
    echo "❌ No existe ${BENCH_DIR}." >&2
    exit 1
fi

if [[ ! -f "${BENCH_DIR}/Procfile" ]]; then
    echo "❌ ${BENCH_DIR} no parece ser un bench válido (falta Procfile)." >&2
    exit 1
fi

# Verificar conectividad a GitHub
if ! curl -fsS --max-time 10 https://github.com > /dev/null; then
    echo "❌ Sin conectividad a GitHub." >&2
    exit 1
fi

echo "   ✅ Validaciones OK"

# ----------------------------------------------------------------------
# Log
# ----------------------------------------------------------------------
LOG_FILE="/home/${FRAPPE_USER}/logs/download-apps-$(date +%Y%m%d-%H%M%S).log"
mkdir -p "$(dirname "${LOG_FILE}")"
exec > >(tee -a "${LOG_FILE}") 2>&1

echo "📝 Log: ${LOG_FILE}"
echo "🕐 Inicio: $(date)"

cd "${BENCH_DIR}"

# ----------------------------------------------------------------------
# Descargar apps
# ----------------------------------------------------------------------

echo "📦 [2/4] Descargando apps (branch: ${FRAPPE_BRANCH})..."

DOWNLOADED=()
SKIPPED=()
FAILED=()

for APP_ENTRY in "${APPS[@]}"; do
    APP_NAME="${APP_ENTRY%%|*}"
    APP_URL="${APP_ENTRY##*|}"

    echo ""
    echo "━━━ ${APP_NAME} ━━━"

    if [[ -d "apps/${APP_NAME}" ]]; then
        # Verificar que la branch es la correcta
        CURRENT_BRANCH=$(git -C "apps/${APP_NAME}" rev-parse --abbrev-ref HEAD 2>/dev/null || echo "unknown")
        echo "   ℹ️  Ya existe (branch actual: ${CURRENT_BRANCH})"

        if [[ "${CURRENT_BRANCH}" != "${FRAPPE_BRANCH}" ]]; then
            echo "   ⚠️  Branch no coincide con ${FRAPPE_BRANCH}. Considera:"
            echo "      bench switch-to-branch ${FRAPPE_BRANCH} ${APP_NAME}"
        fi
        SKIPPED+=("${APP_NAME}")
    else
        echo "   📥 Descargando desde ${APP_URL}..."

        if bench get-app --branch "${FRAPPE_BRANCH}" --resolve-deps "${APP_URL}"; then
            echo "   ✅ ${APP_NAME} descargado"
            DOWNLOADED+=("${APP_NAME}")
        else
            echo "   ❌ Falló descarga de ${APP_NAME}"
            FAILED+=("${APP_NAME}")
        fi
    fi
done

# ----------------------------------------------------------------------
# Resumen
# ----------------------------------------------------------------------

echo ""
echo "🔍 [3/4] Resumen de descargas..."

if [[ ${#DOWNLOADED[@]} -gt 0 ]]; then
    echo "   ✅ Descargadas: ${DOWNLOADED[*]}"
fi

if [[ ${#SKIPPED[@]} -gt 0 ]]; then
    echo "   ⏭️  Ya existían: ${SKIPPED[*]}"
fi

if [[ ${#FAILED[@]} -gt 0 ]]; then
    echo "   ❌ Fallaron: ${FAILED[*]}"
    exit 1
fi

# ----------------------------------------------------------------------
# Listar apps del bench
# ----------------------------------------------------------------------

echo ""
echo "📋 [4/4] Apps disponibles en el bench:"
bench list-apps --format json 2>/dev/null | python3 -c "
import json, sys
apps = json.load(sys.stdin)
for app in apps:
    print(f'   - {app}')
" 2>/dev/null || ls -1 apps/ | sed 's/^/   - /'

echo ""
echo "━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━"
echo "✅ Descarga de apps completada"
echo "━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━"
echo ""
echo "🕐 Fin: $(date)"
echo ""
echo "ℹ️  Próximo paso: instalar apps en los sitios con create-site.sh"
echo "   Ejemplo: bench --site tic.wdstudio.com.bo install-app erpnext payments hrms"
