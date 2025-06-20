#!/bin/bash
set -e

BENCH_DIR="/home/frappe/erpnext-bench"
FRAPPE_BRANCH="version-15"

cd "$BENCH_DIR"

# Instalar apps necesarias
echo "📦 Obteniendo la app ERPNext..."
bench get-app erpnext --branch "$FRAPPE_BRANCH"

echo "💳 Obteniendo app 'hrms'..."
bench get-app hrms --branch "$FRAPPE_BRANCH"

# Puedes seguir agregando más aquí
# bench get-app hrms --branch "$FRAPPE_BRANCH"

echo "✅ Todas las apps fueron obtenidas correctamente."
