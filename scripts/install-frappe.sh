#!/bin/bash
set -e

echo "🚀 Instalando Frappe Bench..."

# Validar usuario
if [ "$(whoami)" != "frappe" ]; then
  echo "❌ Este script debe ejecutarse como el usuario 'frappe'."
  exit 1
fi

# Verificar instalación de bench CLI
if ! command -v bench &> /dev/null; then
  echo "📦 Instalando Frappe Bench CLI..."
  sudo pip3 install frappe-bench
else
  echo "✔️ 'bench' ya está instalado."
fi

# Verificar versión
echo "🔍 Verificando versión de Bench..."
bench --version

# Variables
FRAPPE_BRANCH=version-15
BENCH_DIR=frappe-bench
BENCH_PATH="/home/frappe/$BENCH_DIR"

# Validar directorio home
if [ ! -d "/home/frappe" ]; then
  echo "❌ El directorio /home/frappe no existe. Verifica el usuario."
  exit 1
fi

# Validar si ya existe el bench
if [ -d "$BENCH_PATH" ]; then
  echo "⚠️ Ya existe la carpeta $BENCH_PATH. Abortando para evitar sobreescribir."
  exit 1
fi

# Crear el bench
echo "🏗️ Creando bench en $BENCH_PATH con Frappe $FRAPPE_BRANCH..."
cd /home/frappe
bench init "$BENCH_DIR" --frappe-branch "$FRAPPE_BRANCH"

echo "🎉 Bench inicializado correctamente en: $BENCH_PATH"
