#!/bin/bash
set -e

export DEBIAN_FRONTEND=noninteractive

echo "🔄 Actualizando índices de paquetes..."
sudo apt-get update -y

echo "📦 Actualizando paquetes del sistema (manteniendo tus configuraciones existentes)..."
sudo apt-get -y -q \
    -o Dpkg::Options::="--force-confdef" \
    -o Dpkg::Options::="--force-confold" \
    dist-upgrade

echo "✅ Sistema actualizado sin intervención manual."