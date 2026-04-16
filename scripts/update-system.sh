#!/bin/bash
#
# update-system.sh - Actualiza paquetes del sistema de forma no interactiva
# Uso: sudo ./update-system.sh
#

set -euo pipefail
export DEBIAN_FRONTEND=noninteractive

# Verificar privilegios
if [[ $EUID -ne 0 ]]; then
    echo "❌ Este script debe ejecutarse como root o con sudo." >&2
    exit 1
fi

# Log a archivo además de stdout
LOG_FILE="/var/log/update-system-$(date +%Y%m%d-%H%M%S).log"
exec > >(tee -a "$LOG_FILE") 2>&1

echo "📝 Log: $LOG_FILE"
echo "🕐 Inicio: $(date)"

# Esperar a que apt se libere (unattended-upgrades puede estar corriendo)
echo "⏳ [1/5] Esperando locks de apt..."
while fuser /var/lib/dpkg/lock-frontend >/dev/null 2>&1 || \
      fuser /var/lib/apt/lists/lock >/dev/null 2>&1 || \
      fuser /var/lib/dpkg/lock >/dev/null 2>&1; do
    echo "   ...otro proceso apt está corriendo, esperando 5s"
    sleep 5
done

echo "🔄 [2/5] Actualizando índices de paquetes..."
apt-get update -y

echo "📦 [3/5] Actualizando paquetes del sistema..."
apt-get -y -q \
    -o Dpkg::Options::="--force-confdef" \
    -o Dpkg::Options::="--force-confold" \
    full-upgrade

echo "🧹 [4/5] Limpiando paquetes obsoletos..."
apt-get autoremove -y --purge
apt-get autoclean -y
apt-get clean

echo "🔍 [5/5] Verificando si requiere reinicio..."
if [[ -f /var/run/reboot-required ]]; then
    echo "⚠️  El sistema requiere un REINICIO para completar la actualización."
    if [[ -f /var/run/reboot-required.pkgs ]]; then
        echo "   Paquetes que requieren reinicio:"
        sed 's/^/     - /' /var/run/reboot-required.pkgs
    fi
    echo "   Ejecuta: sudo reboot"
else
    echo "✅ No se requiere reinicio."
fi

echo "🕐 Fin: $(date)"
echo "✅ Sistema actualizado correctamente."
