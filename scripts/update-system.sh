#!/bin/bash
set -euo pipefail

export DEBIAN_FRONTEND=noninteractive

echo "🔄 [1/3] Actualizando índices de paquetes..."
sudo apt-get update -y

echo "📦 [2/3] Actualizando paquetes del sistema..."
sudo apt-get -y -q \
    -o Dpkg::Options::="--force-confdef" \
    -o Dpkg::Options::="--force-confold" \
    dist-upgrade

echo "🧹 [3/3] Limpiando paquetes obsoletos..."
sudo apt-get autoremove -y
sudo apt-get clean

echo "✅ Sistema actualizado correctamente sin intervención manual."
