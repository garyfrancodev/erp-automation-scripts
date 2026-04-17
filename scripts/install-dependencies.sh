#!/bin/bash
#
# install-dependencies.sh - Instala dependencias del sistema para Frappe v15
# Requisitos: Ubuntu 22.04 LTS
# Uso: sudo ./install-dependencies.sh
#

set -euo pipefail
export DEBIAN_FRONTEND=noninteractive

# Verificar privilegios
if [[ $EUID -ne 0 ]]; then
    echo "❌ Este script debe ejecutarse como root o con sudo." >&2
    exit 1
fi

# Verificar que es Ubuntu 22.04
if ! grep -q "Ubuntu 22.04" /etc/os-release; then
    echo "⚠️  Este script está diseñado para Ubuntu 22.04. Detectado:"
    grep "PRETTY_NAME" /etc/os-release
    read -rp "¿Continuar de todos modos? [y/N] " resp
    [[ "$resp" =~ ^[Yy]$ ]] || exit 1
fi

# Log a archivo
LOG_FILE="/var/log/install-dependencies-$(date +%Y%m%d-%H%M%S).log"
exec > >(tee -a "$LOG_FILE") 2>&1

echo "📝 Log: $LOG_FILE"
echo "🕐 Inicio: $(date)"

# ----------------------------------------------------------------------
# 1. Actualizar índices
# ----------------------------------------------------------------------
echo "🔄 [1/8] Actualizando índices de paquetes..."
apt-get update -y

# ----------------------------------------------------------------------
# 2. Dependencias base del sistema + Frappe v15
# ----------------------------------------------------------------------
echo "📦 [2/8] Instalando dependencias del sistema..."
apt-get install -y \
    git \
    curl \
    wget \
    gnupg \
    ca-certificates \
    software-properties-common \
    build-essential \
    jq \
    supervisor \
    nginx \
    certbot \
    python3-certbot-nginx \
    python-is-python3 \
    python3-dev \
    python3-pip \
    python3-venv \
    python3-setuptools \
    libffi-dev \
    libssl-dev \
    libmysqlclient-dev \
    redis-server \
    fontconfig \
    libfontconfig1 \
    libxrender1 \
    libxext6 \
    xfonts-75dpi \
    xfonts-base \
    xvfb

# ----------------------------------------------------------------------
# 3. Eliminar versiones conflictivas de Node.js
# ----------------------------------------------------------------------
echo "🧼 [3/8] Eliminando versiones conflictivas de Node.js..."
apt-get remove --purge -y nodejs npm libnode72 libnode-dev nodejs-doc 2>/dev/null || true
apt-get autoremove -y
apt-get autoclean -y

# ----------------------------------------------------------------------
# 4. Node.js 18 LTS desde NodeSource
# ----------------------------------------------------------------------
echo "📦 [4/8] Instalando Node.js 18 LTS desde NodeSource..."
curl -fsSL https://deb.nodesource.com/setup_18.x | bash -
apt-get install -y nodejs

NODE_VERSION=$(node -v)
NPM_VERSION=$(npm -v)
echo "   ✅ Node.js: $NODE_VERSION"
echo "   ✅ npm: $NPM_VERSION"

# ----------------------------------------------------------------------
# 5. Yarn 1.x (classic) — Frappe requiere Yarn classic, no Yarn berry
# ----------------------------------------------------------------------
echo "📦 [5/8] Instalando Yarn classic..."
npm install -g yarn@1.22.22
echo "   ✅ Yarn: $(yarn --version)"

# ----------------------------------------------------------------------
# 6. wkhtmltopdf 0.12.6.1 con Qt patched
# ----------------------------------------------------------------------
echo "🖨️  [6/8] Instalando wkhtmltopdf 0.12.6.1 (Qt patched)..."
WKHTML_VERSION="0.12.6.1-2"
WKHTML_DEB="wkhtmltox_${WKHTML_VERSION}.jammy_amd64.deb"
WKHTML_URL="https://github.com/wkhtmltopdf/packaging/releases/download/${WKHTML_VERSION}/${WKHTML_DEB}"
WKHTML_SHA256="ee88d74834bdec650f7432c7d3ef1c981e42ae7a762a75a01f7f5da59abc18d5"

cd /tmp
wget -q "$WKHTML_URL" -O "$WKHTML_DEB"

# Verificar checksum
echo "${WKHTML_SHA256}  ${WKHTML_DEB}" | sha256sum -c - || {
    echo "❌ Checksum de wkhtmltopdf no coincide. Abortando."
    rm -f "$WKHTML_DEB"
    exit 1
}

apt-get install -y "./${WKHTML_DEB}"
rm -f "$WKHTML_DEB"
cd -

echo "   ✅ wkhtmltopdf: $(wkhtmltopdf --version)"

# ----------------------------------------------------------------------
# 7. Configurar Redis para Frappe (no arrancar como servicio de sistema)
# ----------------------------------------------------------------------
echo "⚙️  [7/8] Configurando Redis..."
# Frappe usa sus propios Redis (cache, queue, socketio) vía supervisor
# Desactivar el Redis de sistema para evitar conflicto con el puerto 6379
systemctl disable --now redis-server 2>/dev/null || true
echo "   ✅ Redis de sistema deshabilitado (Frappe usará sus propias instancias)"

# ----------------------------------------------------------------------
# 8. Verificación final
# ----------------------------------------------------------------------
echo "🔍 [8/8] Verificación de versiones instaladas..."
echo ""
echo "━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━"
echo "  Python:      $(python3 --version)"
echo "  pip:         $(pip3 --version | awk '{print $2}')"
echo "  Node.js:     $(node -v)"
echo "  npm:         $(npm -v)"
echo "  Yarn:        $(yarn --version)"
echo "  Nginx:       $(nginx -v 2>&1 | awk -F/ '{print $2}')"
echo "  Supervisor:  $(supervisord -v)"
echo "  wkhtmltopdf: $(wkhtmltopdf --version)"
echo "  Redis CLI:   $(redis-cli --version | awk '{print $2}')"
echo "  Git:         $(git --version | awk '{print $3}')"
echo "━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━"

echo ""
echo "🕐 Fin: $(date)"
echo "✅ Dependencias del sistema instaladas correctamente."
echo ""
echo "⚠️  Siguiente paso: instalar MariaDB (script separado)."
