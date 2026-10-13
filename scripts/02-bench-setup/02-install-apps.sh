#!/bin/bash
source "$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)/core/lib.sh"

require_user "$FRAPPE_USER"
require_bench

cd "$BENCH_PATH"

echo "⏳ Obteniendo aplicaciones para el Bench: $BENCH_APPS"
echo "   La descarga y compilación de ERPNext puede tomar varios minutos. Por favor espera..."

for app in $BENCH_APPS; do
  if [ -d "apps/$app" ]; then
    echo "ℹ️ La app '$app' ya está descargada. Saltando..."
  else
    echo "📦 Obteniendo la app '$app' ($FRAPPE_BRANCH)..."
    bench get-app "$app" --branch "$FRAPPE_BRANCH"
  fi
done

echo "✅ Todas las apps fueron obtenidas correctamente."
