#!/bin/bash
source "$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)/core/lib.sh"

echo "🚀 Instalando Frappe Bench..."

require_user "$FRAPPE_USER"

if [ ! -d "$FRAPPE_HOME" ]; then
  echo "❌ El directorio $FRAPPE_HOME no existe. Verifica el usuario."
  exit 1
fi

# Bench CLI: se instala con pipx a nivel de sistema (/usr/local/bin) para que
# 'sudo bench setup production ...' lo encuentre y para evitar el error PEP 668
# de 'pip install' en Ubuntu 23.04+.
if ! command -v bench &>/dev/null; then
  echo "📦 Instalando Frappe Bench CLI (pipx)..."
  require_cmd pipx "Ejecuta primero scripts/01-server-setup/04-install-dependencies.sh"
  sudo env PIPX_HOME=/opt/pipx PIPX_BIN_DIR=/usr/local/bin pipx install frappe-bench
else
  echo "✔️ 'bench' ya está instalado."
fi

# Frappe Bench >= 5.31 requiere 'uv' para la creación y gestión del venv
if ! command -v uv &>/dev/null; then
  echo "📦 Instalando uv (gestor de paquetes requerido por Frappe Bench)..."
  sudo env PIPX_HOME=/opt/pipx PIPX_BIN_DIR=/usr/local/bin pipx install uv \
    || curl -LsSf https://astral.sh/uv/install.sh | sudo env UV_INSTALL_DIR=/usr/local/bin sh
else
  echo "✔️ 'uv' ya está instalado."
fi

echo "🔍 Verificando versiones..."
bench --version
uv --version

require_cmd node "Ejecuta primero scripts/01-server-setup/04-install-dependencies.sh"
require_cmd yarn "Ejecuta primero scripts/01-server-setup/04-install-dependencies.sh"
require_cmd redis-server "Ejecuta primero scripts/01-server-setup/04-install-dependencies.sh"

if [ -d "$BENCH_PATH" ]; then
  if [ ! -d "$BENCH_PATH/apps/frappe" ]; then
    echo "⚠️ Se detectó una carpeta incompleta en $BENCH_PATH (posible fallo previo de bench init)."
    echo "   Limpiando $BENCH_PATH para permitir una inicialización limpia..."
    rm -rf "$BENCH_PATH"
  else
    echo "⚠️ Ya existe un Bench válido en $BENCH_PATH. Abortando para evitar sobreescribir."
    exit 1
  fi
fi

echo "🏗️ Creando bench en $BENCH_PATH con Frappe $FRAPPE_BRANCH..."
echo "⏳ 'bench init' descargará e instalará el entorno virtual, paquetes de Python y librerías Node."
echo "   Este proceso toma habitualmente entre 5 y 10 minutos. Por favor no cierres la terminal..."
cd "$FRAPPE_HOME"
bench init "$BENCH_NAME" --frappe-branch "$FRAPPE_BRANCH"

echo "🎉 Bench inicializado correctamente en: $BENCH_PATH"

