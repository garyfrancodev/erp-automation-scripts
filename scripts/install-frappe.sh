#!/bin/bash
set -e

echo "🚀 Instalando Frappe Bench..."

# Instalar frappe-bench CLI
sudo pip3 install frappe-bench --break-system-packages

echo "🔍 Verificando versión de Bench..."
bench --version

# Inicializar banco de trabajo (cambia el nombre si lo deseas)
BENCH_DIR=erpnext-bench
FRAPPE_BRANCH=version-15

echo "🏗️ Creando bench en $BENCH_DIR con Frappe $FRAPPE_BRANCH..."
bench init $BENCH_DIR --frappe-branch $FRAPPE_BRANCH

cd $BENCH_DIR

echo "📦 Obteniendo la app ERPNext..."
bench get-app erpnext --branch $FRAPPE_BRANCH