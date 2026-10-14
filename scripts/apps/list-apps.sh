#!/bin/bash
source "$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)/core/lib.sh"

require_bench
cd "$BENCH_PATH"

echo "========================================"
echo "📦 Aplicaciones instaladas en el Bench:"
echo "========================================"
if [ -d "apps" ]; then
  for a in apps/*/; do
    if [ -d "$a" ]; then
      app_name="$(basename "$a")"
      branch="$(git -C "$a" branch --show-current 2>/dev/null || echo "desconocido")"
      commit="$(git -C "$a" log -1 --format="%h - %s" 2>/dev/null || echo "")"
      echo "  • $app_name ($branch) $commit"
    fi
  done
else
  echo "  (No hay carpeta apps/)"
fi
echo "========================================"
