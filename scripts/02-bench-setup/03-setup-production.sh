#!/bin/bash
source "$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)/core/lib.sh"

require_bench
cd "$BENCH_PATH"

echo "🌐 Activando modo multisitio por dominio (DNS multitenant)..."
as_frappe bench config dns_multitenant on

# 'setup production' ya genera supervisor + nginx, así que no hace falta
# 'bench setup supervisor' por separado. Necesita root: se usa la ruta absoluta
# de bench porque 'sudo' no hereda el PATH del usuario.
echo "🔧 Configurando producción (usuario: $FRAPPE_USER)..."
sudo "$(command -v bench)" setup production "$FRAPPE_USER" --yes

echo "📋 Estado de los servicios:"
sudo supervisorctl status || true
sudo systemctl is-active nginx

echo "⏰ Configurando respaldos automáticos en el crontab del usuario $FRAPPE_USER..."
as_frappe bench setup backups

echo "✅ Producción lista con Nginx, Supervisor, multisitio activado y backups automáticos."
