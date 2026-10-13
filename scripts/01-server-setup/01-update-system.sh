#!/bin/bash
source "$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)/core/lib.sh"

echo "🔄 [1/3] Actualizando índices de paquetes..."
apt_get update -y

echo "📦 [2/3] Actualizando paquetes del sistema..."
apt_get -y -q \
    -o Dpkg::Options::="--force-confdef" \
    -o Dpkg::Options::="--force-confold" \
    dist-upgrade

echo "🧹 [3/3] Limpiando paquetes obsoletos..."
apt_get autoremove -y
apt_get clean

echo "✅ Sistema actualizado correctamente sin intervención manual."
if [ -f /var/run/reboot-required ]; then
  echo "⚠️  El sistema pide reinicio (kernel/librerías). Reinicia cuando puedas: sudo reboot"
fi
