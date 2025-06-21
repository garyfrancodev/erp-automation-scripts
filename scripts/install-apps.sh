#!/bin/bash
set -e

BENCH_DIR="/home/frappe/erpnext-bench"
FRAPPE_BRANCH="version-15"

if ! command -v bench &> /dev/null; then
  echo "❌ El comando 'bench' no está disponible. Asegúrate de tenerlo instalado."
  exit 1
fi

cd "$BENCH_DIR"

if [ ! -f "Procfile" ]; then
  echo "❌ Este directorio no parece ser un bench válido. Abortando."
  exit 1
fi

# Instalar ERPNext si no está
if [ -d "apps/erpnext" ]; then
  echo "ℹ️ La app 'erpnext' ya está instalada. Saltando..."
else
  echo "📦 Obteniendo la app ERPNext..."
  bench get-app erpnext --branch "$FRAPPE_BRANCH"
fi

# Instalar HRMS si no está
if [ -d "apps/hrms" ]; then
  echo "ℹ️ La app 'hrms' ya está instalada. Saltando..."
else
  echo "💳 Obteniendo app 'hrms'..."
  bench get-app hrms --branch "$FRAPPE_BRANCH"
fi

echo "✅ Todas las apps fueron obtenidas correctamente."
