#!/bin/bash
#
# install-frappe.sh - Instala Frappe Bench v15
# Requisitos: ejecutar como usuario 'frappe' (no root)
# Pre-requisitos: sistema actualizado, dependencias instaladas, MariaDB configurado
#

set -euo pipefail

# ----------------------------------------------------------------------
# Configuración
# ----------------------------------------------------------------------
FRAPPE_USER="frappe"
FRAPPE_HOME="/home/${FRAPPE_USER}"
FRAPPE_BRANCH="version-15"
PYTHON_VERSION="python3.10"
BENCH_DIR="frappe-bench"
BENCH_PATH="${FRAPPE_HOME}/${BENCH_DIR}"
BENCH_VENV="${FRAPPE_HOME}/.bench-venv"

# ----------------------------------------------------------------------
# Validaciones iniciales
# ----------------------------------------------------------------------

echo "🔍 [1/7] Validando entorno..."

# 1. Debe correr como usuario frappe (NO root)
if [[ "$(whoami)" != "${FRAPPE_USER}" ]]; then
    echo "❌ Este script debe ejecutarse como el usuario '${FRAPPE_USER}'." >&2
    echo "   Ejecuta: sudo su - ${FRAPPE_USER}" >&2
    exit 1
fi

# 2. No debe correr con privilegios elevados
if [[ $EUID -eq 0 ]]; then
    echo "❌ Este script NO debe ejecutarse como root." >&2
    exit 1
fi

# 3. Validar directorio home
if [[ ! -d "${FRAPPE_HOME}" ]]; then
    echo "❌ El directorio ${FRAPPE_HOME} no existe." >&2
    exit 1
fi

# 4. Validar que Python 3.10 está instalado
if ! command -v "${PYTHON_VERSION}" &> /dev/null; then
    echo "❌ ${PYTHON_VERSION} no está instalado. Corre antes install-dependencies.sh" >&2
    exit 1
fi

# 5. Validar dependencias críticas del sistema
for cmd in git node npm yarn wkhtmltopdf mysql redis-cli; do
    if ! command -v "$cmd" &> /dev/null; then
        echo "❌ '$cmd' no está instalado. Corre antes los scripts previos." >&2
        exit 1
    fi
done

# 6. Validar que MariaDB está corriendo
if ! systemctl is-active --quiet mariadb; then
    echo "❌ MariaDB no está corriendo. Inicia con: sudo systemctl start mariadb" >&2
    exit 1
fi

# 7. Validar conectividad a GitHub (bench init clona de ahí)
if ! curl -fsS --max-time 10 https://github.com > /dev/null; then
    echo "❌ No hay conectividad a GitHub. Verifica tu red." >&2
    exit 1
fi

echo "   ✅ Todas las validaciones pasaron"

# ----------------------------------------------------------------------
# Instalar bench CLI en virtualenv dedicado (sin sudo)
# ----------------------------------------------------------------------

echo "📦 [2/7] Instalando bench CLI en virtualenv dedicado..."

if [[ ! -d "${BENCH_VENV}" ]]; then
    "${PYTHON_VERSION}" -m venv "${BENCH_VENV}"
    echo "   ✅ Virtualenv creado en ${BENCH_VENV}"
else
    echo "   ℹ️  Virtualenv ya existe en ${BENCH_VENV}"
fi

# Actualizar pip y herramientas dentro del venv
"${BENCH_VENV}/bin/pip" install --quiet --upgrade pip setuptools wheel

# Instalar frappe-bench en el venv
if ! "${BENCH_VENV}/bin/pip" show frappe-bench &> /dev/null; then
    echo "   📥 Instalando frappe-bench..."
    "${BENCH_VENV}/bin/pip" install --quiet frappe-bench
else
    echo "   ℹ️  frappe-bench ya instalado, actualizando..."
    "${BENCH_VENV}/bin/pip" install --quiet --upgrade frappe-bench
fi

# Crear symlink para que 'bench' esté disponible en el PATH
mkdir -p "${FRAPPE_HOME}/.local/bin"
ln -sf "${BENCH_VENV}/bin/bench" "${FRAPPE_HOME}/.local/bin/bench"

# Asegurar que ~/.local/bin está en el PATH (persistir en .bashrc)
if ! grep -q 'HOME/.local/bin' "${FRAPPE_HOME}/.bashrc" 2>/dev/null; then
    echo 'export PATH="$HOME/.local/bin:$PATH"' >> "${FRAPPE_HOME}/.bashrc"
    echo "   ✅ Agregado ~/.local/bin al PATH en .bashrc"
fi

# Exportar para esta sesión
export PATH="${FRAPPE_HOME}/.local/bin:${PATH}"

# Verificar
BENCH_VERSION=$(bench --version 2>&1 || echo "error")
echo "   ✅ bench CLI versión: ${BENCH_VERSION}"

# ----------------------------------------------------------------------
# Verificar estado del bench existente
# ----------------------------------------------------------------------

echo "🔍 [3/7] Verificando bench existente..."

if [[ -d "${BENCH_PATH}" ]]; then
    # ¿Está completo o corrupto?
    if [[ -f "${BENCH_PATH}/sites/common_site_config.json" ]] && \
       [[ -d "${BENCH_PATH}/apps/frappe" ]] && \
       [[ -d "${BENCH_PATH}/env" ]]; then
        echo "   ⚠️  Ya existe un bench funcional en ${BENCH_PATH}"
        echo "   Para reinstalar desde cero, elimina manualmente:"
        echo "     rm -rf ${BENCH_PATH}"
        exit 0
    else
        echo "   ⚠️  Existe ${BENCH_PATH} pero está INCOMPLETO o CORRUPTO"
        echo "   Se detectaron estos archivos/directorios faltantes:"
        [[ ! -f "${BENCH_PATH}/sites/common_site_config.json" ]] && echo "     - sites/common_site_config.json"
        [[ ! -d "${BENCH_PATH}/apps/frappe" ]] && echo "     - apps/frappe"
        [[ ! -d "${BENCH_PATH}/env" ]] && echo "     - env (virtualenv)"
        echo ""
        read -rp "¿Eliminar y reinstalar? [y/N] " resp
        if [[ "$resp" =~ ^[Yy]$ ]]; then
            rm -rf "${BENCH_PATH}"
            echo "   🗑️  Directorio eliminado"
        else
            echo "   Abortado por el usuario."
            exit 1
        fi
    fi
fi

# ----------------------------------------------------------------------
# Inicializar bench
# ----------------------------------------------------------------------

echo "🏗️  [4/7] Inicializando bench (esto puede tardar 5-15 minutos)..."
echo "   Branch:  ${FRAPPE_BRANCH}"
echo "   Python:  ${PYTHON_VERSION}"
echo "   Path:    ${BENCH_PATH}"
echo ""

cd "${FRAPPE_HOME}"

bench init "${BENCH_DIR}" \
    --frappe-branch "${FRAPPE_BRANCH}" \
    --python "${PYTHON_VERSION}" \
    --verbose

# ----------------------------------------------------------------------
# Verificar instalación
# ----------------------------------------------------------------------

echo "🔍 [5/7] Verificando instalación..."

if [[ ! -d "${BENCH_PATH}/apps/frappe" ]]; then
    echo "❌ Frappe no se instaló correctamente." >&2
    exit 1
fi

cd "${BENCH_PATH}"

FRAPPE_INSTALLED_VERSION=$(bench version --format plain 2>/dev/null | grep frappe | awk '{print $2}' || echo "unknown")
echo "   ✅ Frappe instalado: ${FRAPPE_INSTALLED_VERSION}"

# ----------------------------------------------------------------------
# Configurar common_site_config.json para multi-tenant
# ----------------------------------------------------------------------

echo "⚙️  [6/7] Configurando multi-tenant..."

# Habilitar DNS multi-tenant (cada sitio por su dominio)
bench config dns_multitenant on
echo "   ✅ DNS multi-tenant habilitado"

# ----------------------------------------------------------------------
# Permisos del directorio home (Nginx necesita acceso para servir assets)
# ----------------------------------------------------------------------

echo "🔐 [7/7] Ajustando permisos..."

# Nginx corre como www-data y necesita leer los assets públicos en /home/frappe/frappe-bench/sites/
chmod o+rx "${FRAPPE_HOME}"
echo "   ✅ Permisos de ${FRAPPE_HOME} ajustados (o+rx) para Nginx"

# ----------------------------------------------------------------------
# Resumen final
# ----------------------------------------------------------------------

echo ""
echo "━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━"
echo "✅ Frappe Bench ${FRAPPE_BRANCH} instalado"
echo "━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━"
echo "  Ubicación:       ${BENCH_PATH}"
echo "  Python:          ${PYTHON_VERSION}"
echo "  Branch:          ${FRAPPE_BRANCH}"
echo "  Versión Frappe:  ${FRAPPE_INSTALLED_VERSION}"
echo "  Multi-tenant:    habilitado"
echo "  bench CLI:       ${FRAPPE_HOME}/.local/bin/bench"
echo "━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━"
echo ""
echo "🕐 Fin: $(date)"
echo ""
echo "ℹ️  Próximos pasos:"
echo "   1. Instalar apps:     cd ${BENCH_PATH} && bench get-app erpnext --branch version-15"
echo "   2. Crear primer sitio: bench new-site tic.ingetrans.com --mariadb-root-password <pass>"
echo "   3. Configurar producción: sudo bench setup production ${FRAPPE_USER}"
