#!/bin/bash
#
# setup-production.sh - Configura Frappe en modo producción (Supervisor + Nginx)
# Requisitos: ejecutar como usuario 'frappe' con sudo granular configurado
# Pre-requisitos: bench inicializado, al menos 1 app instalada, al menos 1 sitio creado
#

set -euo pipefail

# ----------------------------------------------------------------------
# Configuración
# ----------------------------------------------------------------------
FRAPPE_USER="frappe"
BENCH_DIR="/home/${FRAPPE_USER}/frappe-bench"

# ----------------------------------------------------------------------
# Validaciones iniciales
# ----------------------------------------------------------------------

echo "🔍 [1/8] Validando entorno..."

# 1. Debe correr como usuario frappe (NO root)
if [[ "$(whoami)" != "${FRAPPE_USER}" ]]; then
    echo "❌ Este script debe ejecutarse como el usuario '${FRAPPE_USER}'." >&2
    echo "   Ejecuta: sudo su - ${FRAPPE_USER}" >&2
    exit 1
fi

if [[ $EUID -eq 0 ]]; then
    echo "❌ Este script NO debe ejecutarse como root." >&2
    exit 1
fi

# 2. Verificar que existe el bench
if [[ ! -d "${BENCH_DIR}" ]]; then
    echo "❌ No existe ${BENCH_DIR}. Corre install-frappe.sh primero." >&2
    exit 1
fi

# 3. Verificar que bench está en PATH
if ! command -v bench &> /dev/null; then
    echo "❌ 'bench' no está en el PATH. Revisa ~/.local/bin y .bashrc" >&2
    exit 1
fi

# 4. Verificar que hay al menos un sitio creado
cd "${BENCH_DIR}"
SITES=$(find sites -maxdepth 1 -mindepth 1 -type d ! -name "assets" 2>/dev/null | wc -l)
if [[ "${SITES}" -eq 0 ]]; then
    echo "❌ No hay sitios creados. Crea al menos uno con:" >&2
    echo "   bench new-site tic.ingetrans.com --mariadb-root-password <pass> --admin-password <pass>" >&2
    exit 1
fi

# 5. Verificar que sudo granular funciona
if ! sudo -n -l | grep -q supervisorctl; then
    echo "❌ El usuario ${FRAPPE_USER} no tiene permisos sudo para supervisorctl." >&2
    echo "   Corre create-frappe-user.sh primero." >&2
    exit 1
fi

# 6. Verificar que supervisor y nginx están instalados
for svc in supervisor nginx; do
    if ! command -v "${svc}" &> /dev/null && ! command -v "${svc}ctl" &> /dev/null; then
        echo "❌ ${svc} no está instalado." >&2
        exit 1
    fi
done

echo "   ✅ Todas las validaciones pasaron"
echo "   ℹ️  Sitios detectados: ${SITES}"

# ----------------------------------------------------------------------
# Log
# ----------------------------------------------------------------------
LOG_FILE="/home/${FRAPPE_USER}/logs/setup-production-$(date +%Y%m%d-%H%M%S).log"
mkdir -p "$(dirname "${LOG_FILE}")"
exec > >(tee -a "${LOG_FILE}") 2>&1

echo "📝 Log: ${LOG_FILE}"
echo "🕐 Inicio: $(date)"

# ----------------------------------------------------------------------
# 2. Habilitar DNS multi-tenant (idempotente)
# ----------------------------------------------------------------------

echo "🌐 [2/8] Verificando modo multi-tenant..."

cd "${BENCH_DIR}"

MULTITENANT=$(bench get-config dns_multitenant 2>/dev/null || echo "false")
if [[ "${MULTITENANT}" == "True" ]] || [[ "${MULTITENANT}" == "true" ]]; then
    echo "   ✅ DNS multi-tenant ya habilitado"
else
    bench config dns_multitenant on
    echo "   ✅ DNS multi-tenant habilitado"
fi

# ----------------------------------------------------------------------
# 3. Compilar assets (build)
# ----------------------------------------------------------------------

echo "🏗️  [3/8] Compilando assets de producción..."

# bench build genera los bundles JS/CSS optimizados
bench build --production
echo "   ✅ Assets compilados"

# ----------------------------------------------------------------------
# 4. Configurar Supervisor
# ----------------------------------------------------------------------

echo "⚙️  [4/8] Configurando Supervisor..."

# bench setup supervisor genera config/supervisor.conf dentro del bench
# Usa --yes para no preguntar si sobrescribir
bench setup supervisor --yes --user "${FRAPPE_USER}"

# Crear symlink para que /etc/supervisor/conf.d/ lea la config del bench
SUPERVISOR_CONF_SRC="${BENCH_DIR}/config/supervisor.conf"
SUPERVISOR_CONF_DST="/etc/supervisor/conf.d/frappe-bench.conf"

if [[ ! -L "${SUPERVISOR_CONF_DST}" ]] || [[ "$(readlink "${SUPERVISOR_CONF_DST}")" != "${SUPERVISOR_CONF_SRC}" ]]; then
    sudo ln -sf "${SUPERVISOR_CONF_SRC}" "${SUPERVISOR_CONF_DST}"
    echo "   ✅ Symlink creado: ${SUPERVISOR_CONF_DST}"
else
    echo "   ℹ️  Symlink de supervisor ya existe"
fi

# ----------------------------------------------------------------------
# 5. Configurar Nginx
# ----------------------------------------------------------------------

echo "🌐 [5/8] Configurando Nginx..."

# bench setup nginx genera config/nginx.conf dentro del bench
bench setup nginx --yes

# Parchear formato de log "main" que no existe en algunos nginx.conf
sed -i 's|access_log  /var/log/nginx/access.log main;|access_log /var/log/nginx/access.log;|g' "${BENCH_DIR}/config/nginx.conf"
sed -i 's|access_log /var/log/nginx/access.log main;|access_log /var/log/nginx/access.log;|g' "${BENCH_DIR}/config/nginx.conf"

# Crear symlink para que Nginx lea la config del bench
NGINX_CONF_SRC="${BENCH_DIR}/config/nginx.conf"
NGINX_CONF_DST="/etc/nginx/conf.d/frappe-bench.conf"

if [[ ! -L "${NGINX_CONF_DST}" ]] || [[ "$(readlink "${NGINX_CONF_DST}")" != "${NGINX_CONF_SRC}" ]]; then
    sudo ln -sf "${NGINX_CONF_SRC}" "${NGINX_CONF_DST}"
    echo "   ✅ Symlink creado: ${NGINX_CONF_DST}"
else
    echo "   ℹ️  Symlink de nginx ya existe"
fi

# Deshabilitar el sitio default de Nginx (puede chocar con Frappe)
if [[ -L /etc/nginx/sites-enabled/default ]]; then
    sudo rm /etc/nginx/sites-enabled/default
    echo "   ✅ Sitio default de Nginx deshabilitado"
fi

# Validar sintaxis de Nginx antes de recargar
if ! sudo nginx -t > /dev/null 2>&1; then
    echo "❌ Error en la configuración de Nginx:" >&2
    sudo nginx -t
    exit 1
fi
echo "   ✅ Sintaxis de Nginx válida"

# ----------------------------------------------------------------------
# 6. Aplicar permisos correctos
# ----------------------------------------------------------------------

echo "🔐 [6/8] Aplicando permisos..."

# El home de frappe debe ser 'readable+executable' por Nginx (www-data)
sudo chmod o+rx "/home/${FRAPPE_USER}"

# Logs deben ser escribibles por frappe
mkdir -p "${BENCH_DIR}/logs"
chmod 755 "${BENCH_DIR}/logs"

echo "   ✅ Permisos configurados"

# ----------------------------------------------------------------------
# 7. Recargar servicios
# ----------------------------------------------------------------------

echo "🔁 [7/8] Recargando servicios..."

# Supervisor: reread lee nuevas configs, update aplica cambios
sudo supervisorctl reread
sudo supervisorctl update

# Esperar a que los procesos arranquen
sleep 3

# Reiniciar todos los procesos del bench
sudo supervisorctl restart all

# Recargar Nginx (no reiniciar — reload es suficiente y no corta conexiones)
sudo systemctl reload nginx

# Asegurar que los servicios arranquen al boot
sudo systemctl enable nginx
sudo systemctl enable supervisor

echo "   ✅ Servicios recargados y habilitados al boot"

# ----------------------------------------------------------------------
# 8. Verificación final
# ----------------------------------------------------------------------

echo "🔍 [8/8] Verificando estado de producción..."

# Estado de supervisor
echo ""
echo "━━━ Supervisor ━━━"
sudo supervisorctl status | grep -E "frappe-bench|RUNNING|STOPPED|FATAL" || true

# Verificar que todos los procesos de Frappe están RUNNING
FAILED=$(sudo supervisorctl status | grep "frappe-bench" | grep -v "RUNNING" | wc -l)
if [[ "${FAILED}" -gt 0 ]]; then
    echo "⚠️  Hay procesos no corriendo. Revisa logs:" >&2
    sudo supervisorctl status | grep "frappe-bench" | grep -v "RUNNING"
    echo "   Logs en: ${BENCH_DIR}/logs/" >&2
fi

# Estado de Nginx
echo ""
echo "━━━ Nginx ━━━"
if systemctl is-active --quiet nginx; then
    echo "   ✅ Nginx corriendo"
else
    echo "   ❌ Nginx NO corriendo" >&2
fi

# Puertos escuchando
echo ""
echo "━━━ Puertos ━━━"
sudo ss -tlnp | grep -E ':(80|443|8000|9000|11000|12000|13000)' || echo "   ⚠️  Ningún puerto Frappe escuchando"

# ----------------------------------------------------------------------
# Resumen final
# ----------------------------------------------------------------------

echo ""
echo "━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━"
echo "✅ Modo producción configurado"
echo "━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━"
echo "  Bench:           ${BENCH_DIR}"
echo "  Usuario:         ${FRAPPE_USER}"
echo "  Multi-tenant:    habilitado"
echo "  Nginx config:    ${NGINX_CONF_DST}"
echo "  Supervisor:      ${SUPERVISOR_CONF_DST}"
echo "  Auto-start:      nginx + supervisor habilitados al boot"
echo "━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━"
echo ""
echo "🕐 Fin: $(date)"
echo ""
echo "ℹ️  Próximos pasos:"
echo "   1. Apuntar DNS de tus dominios al IP de este servidor"
echo "   2. Configurar SSL: sudo certbot --nginx -d tic.ingetrans.com"
echo "   3. Para cada sitio nuevo:"
echo "      bench new-site <dominio>"
echo "      bench --site <dominio> install-app erpnext"
echo "      bench setup nginx && sudo systemctl reload nginx"
