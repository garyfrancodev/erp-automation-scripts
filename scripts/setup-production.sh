#!/bin/bash
set -e

BENCH_DIR="/home/frappe/erpnext-bench"
cd "$BENCH_DIR"

echo "🌐 Activando modo multisitio por dominio (DNS multitenant)..."
bench config dns_multitenant on

echo "📦 Configurando Supervisor para Frappe..."
bench setup supervisor

echo "🔧 Configurando producción para el usuario frappe..."
sudo bench setup production frappe

echo "🔁 Reiniciando servicios..."
sudo supervisorctl reread
sudo supervisorctl update
sudo supervisorctl restart all

echo "✅ Producción lista con Nginx, Supervisor y multisitio activado."
