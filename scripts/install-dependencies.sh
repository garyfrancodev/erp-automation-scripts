#!/bin/bash
set -e

echo "📦 Instalando dependencias del sistema..."
sudo apt-get update

sudo apt-get install -y \
  git \
  python-is-python3 \
  python3-dev \
  python3-pip \
  python3-venv \
  fontconfig \
  libxrender1 \
  xfonts-75dpi \
  redis-server \
  software-properties-common \
  build-essential \
  libffi-dev \
  libssl-dev \
  jq \
  certbot \
  python3-certbot-nginx \
  supervisor \
  curl \
  ca-certificates

echo "🧼 Eliminando versiones conflictivas de Node.js..."
sudo apt-get remove --purge -y nodejs npm libnode72 libnode-dev nodejs-doc || true
sudo apt-get autoremove -y
sudo apt-get autoclean -y

echo "📦 Instalando Node.js 18.x desde NodeSource..."
curl -fsSL https://deb.nodesource.com/setup_18.x | sudo -E bash -
sudo apt-get install -y nodejs

echo "✅ Node.js instalado: $(node -v)"
echo "✅ npm instalado: $(npm -v)"

echo "📦 Instalando Yarn globalmente..."
sudo npm install -g yarn

echo "📦 Instalando Ansible..."
sudo add-apt-repository --yes --update ppa:ansible/ansible
sudo apt-get install -y ansible

echo "🖨️ Instalando wkhtmltopdf 0.12.6.1..."
WKHTML_DEB="wkhtmltox_0.12.6.1-2.jammy_amd64.deb"
WKHTML_URL="https://github.com/wkhtmltopdf/packaging/releases/download/0.12.6.1-2/${WKHTML_DEB}"

wget -q --show-progress "$WKHTML_URL" -O "$WKHTML_DEB"
sudo dpkg -i "$WKHTML_DEB" || sudo apt-get install -f -y
rm -f "$WKHTML_DEB"

echo "🔐 Instalando 1Password CLI (op)..."
curl -sS https://downloads.1password.com/linux/keys/1password.asc | sudo gpg --dearmor -o /usr/share/keyrings/1password-archive-keyring.gpg
echo 'deb [signed-by=/usr/share/keyrings/1password-archive-keyring.gpg] https://downloads.1password.com/linux/debian/amd64 stable main' | sudo tee /etc/apt/sources.list.d/1password.list
sudo apt-get update
sudo apt-get install -y 1password-cli

echo "✅ Dependencias del sistema instaladas correctamente."
