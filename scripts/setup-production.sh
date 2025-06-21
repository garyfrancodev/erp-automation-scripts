#!/bin/bash
set -e

BENCH_DIR="/home/frappe/erpnext-bench"
cd "$BENCH_DIR"

echo "🌐 Activando modo multisitio por dominio (DNS multitenant)..."
sudo -u frappe bench config dns_multitenant on

echo "📦 Configurando Supervisor para Frappe..."
sudo -u frappe bench setup supervisor

echo "🔧 Configurando producción (usando user=frappe)..."
bench setup production frappe

echo "🔁 Reiniciando servicios..."
sudo supervisorctl reread
sudo supervisorctl update
sudo supervisorctl restart all

echo "✅ Producción lista con Nginx, Supervisor y multisitio activado."
