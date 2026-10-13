#!/bin/bash
# ============================================================
# Bootstrap de instalación para un nuevo servidor VPS
# Uso en un VPS nuevo (como root):
#   curl -sSL https://raw.githubusercontent.com/garyfrancodev/erp-automation-scripts/main/bootstrap.sh | bash
# O ejecutado localmente:
#   bash bootstrap.sh
# ============================================================
set -Eeuo pipefail

REPO_URL="${REPO_URL:-https://github.com/garyfrancodev/erp-automation-scripts.git}"
TARGET_DIR="${TARGET_DIR:-/opt/erp-automation-scripts}"

echo "=========================================================="
echo "🚀 Bootstrap: Preparación inicial del servidor Frappe Bench"
echo "=========================================================="

if [ "$(id -u)" -ne 0 ]; then
  echo "❌ Este script debe ejecutarse como root (o con sudo)." >&2
  exit 1
fi

# Instalar dependencias mínimas requeridas para clonar y ejecutar
export DEBIAN_FRONTEND=noninteractive
if ! command -v git &>/dev/null || ! command -v curl &>/dev/null; then
  echo "📦 Instalando git, curl y ca-certificates..."
  apt-get update -y -q
  apt-get install -y -q git curl ca-certificates
fi

# Clonar o actualizar el repositorio en el directorio estándar /opt
if [ -d "$TARGET_DIR/.git" ]; then
  echo "🔄 Repositorio detectado en $TARGET_DIR. Actualizando..."
  cd "$TARGET_DIR"
  git pull origin main || true
else
  echo "📥 Clonando repositorio en $TARGET_DIR..."
  mkdir -p "$(dirname "$TARGET_DIR")"
  git clone "$REPO_URL" "$TARGET_DIR"
  cd "$TARGET_DIR"
fi

chmod +x "$TARGET_DIR/erp" "$TARGET_DIR/setup.sh" "$TARGET_DIR"/scripts/*/*.sh
ln -sf "$TARGET_DIR/erp" /usr/local/bin/erp

echo "🚀 Arrancando configuración base del servidor..."
if [ -c /dev/tty ]; then
  exec bash "$TARGET_DIR/setup.sh" </dev/tty
else
  exec bash "$TARGET_DIR/setup.sh"
fi
