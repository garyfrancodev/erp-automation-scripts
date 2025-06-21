#!/bin/bash
set -e

# Este script debe ejecutarse como root
if [ "$(whoami)" != "root" ]; then
  echo "❌ Este script debe ejecutarse como root."
  echo "🔁 Usa: sudo bash install-node-global.sh"
  exit 1
fi

echo "📦 Eliminando Node.js y npm antiguos..."
apt remove -y nodejs npm || true

echo "📦 Instalando Node.js v18 globalmente..."
curl -fsSL https://deb.nodesource.com/setup_18.x | bash -
apt-get install -y nodejs

echo "✅ Node global: $(node -v)"
echo "✅ NPM global:  $(npm -v)"
