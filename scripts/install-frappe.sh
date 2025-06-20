#!/bin/bash
set -e

echo "🚀 Instalando Frappe Bench..."

# Instalar frappe-bench CLI si no está
if ! command -v bench &> /dev/null; then
  sudo pip3 install frappe-bench --break-system-packages
fi

echo "🔍 Verificando versión de Bench..."
bench --version

# Configurar variables
FRAPPE_BRANCH=version-15
BENCH_DIR=erpnext-bench
BENCH_PATH="/home/frappe/$BENCH_DIR"

# Asegurar que el directorio no exista ya
if [ -d "$BENCH_PATH" ]; then
  echo "⚠️ Ya existe la carpeta $BENCH_PATH. Abortando."
  exit 1
fi

# Cambiar a home del usuario frappe y crear el bench
echo "🏗️ Creando bench en $BENCH_PATH con Frappe $FRAPPE_BRANCH..."
cd /home/frappe
bench init "$BENCH_DIR" --frappe-branch "$FRAPPE_BRANCH"

echo "✅ Banco de trabajo creado en: $BENCH_PATH"
