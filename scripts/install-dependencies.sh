#!/bin/bash
set -e

echo "📦 Instalando dependencias generales..."

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
  supervisor

echo "📦 Agregando repositorio oficial de Ansible..."
sudo add-apt-repository --yes --update ppa:ansible/ansible

echo "📦 Instalando Ansible..."
sudo apt-get install -y ansible

echo "🖨️ Instalando wkhtmltopdf..."
wget https://github.com/wkhtmltopdf/packaging/releases/download/0.12.6.1-2/wkhtmltox_0.12.6.1-2.jammy_amd64.deb
sudo dpkg -i wkhtmltox_0.12.6.1-2.jammy_amd64.deb || sudo apt-get install -f -y

echo "📦 Instalando Yarn..."
sudo npm install -g yarn
