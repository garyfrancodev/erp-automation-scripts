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
  npm \
  jq \
  supervisor \
  curl \
  ca-certificates

echo "📦 Agregando repositorio oficial de Ansible..."
sudo add-apt-repository --yes --update ppa:ansible/ansible

echo "📦 Instalando Ansible..."
sudo apt-get install -y ansible

echo "🖨️ Instalando wkhtmltopdf 0.12.6.1..."
WKHTML_DEB="wkhtmltox_0.12.6.1-2.jammy_amd64.deb"
WKHTML_URL="https://github.com/wkhtmltopdf/packaging/releases/download/0.12.6.1-2/${WKHTML_DEB}"

wget -q --show-progress "$WKHTML_URL" -O "$WKHTML_DEB"
sudo dpkg -i "$WKHTML_DEB" || sudo apt-get install -f -y
rm -f "$WKHTML_DEB"

echo "📦 Instalando Yarn globalmente..."
sudo npm install -g yarn

echo "✅ Dependencias del sistema instaladas correctamente."
