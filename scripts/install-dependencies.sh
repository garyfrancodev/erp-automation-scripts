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
  certbot \
  python3-certbot-nginx \
  supervisor \
  curl \
  ca-certificates \
  gnupg

echo "📦 Agregando repositorio oficial de Ansible..."
sudo add-apt-repository --yes --update ppa:ansible/ansible

echo "📦 Instalando Ansible..."
sudo apt-get install -y ansible

echo "🔐 Verificando instalación de 1Password CLI (op)..."
if ! command -v op &>/dev/null; then
  echo "📦 Instalando 1Password CLI..."
  curl -sS https://downloads.1password.com/linux/keys/1password.asc | sudo gpg --dearmor -o /usr/share/keyrings/1password-archive-keyring.gpg
  echo 'deb [signed-by=/usr/share/keyrings/1password-archive-keyring.gpg] https://downloads.1password.com/linux/debian/amd64 stable main' | sudo tee /etc/apt/sources.list.d/1password.list
  sudo apt-get update
  sudo apt-get install -y 1password-cli
else
  echo "✅ 1Password CLI ya instalado: $(op --version)"
fi

echo "🖨️ Instalando wkhtmltopdf 0.12.6.1..."
WKHTML_DEB="wkhtmltox_0.12.6.1-2.jammy_amd64.deb"
WKHTML_URL="https://github.com/wkhtmltopdf/packaging/releases/download/0.12.6.1-2/${WKHTML_DEB}"

wget -q --show-progress "$WKHTML_URL" -O "$WKHTML_DEB"
sudo dpkg -i "$WKHTML_DEB" || sudo apt-get install -f -y
rm -f "$WKHTML_DEB"

echo "📦 Instalando Node.js 18.x globalmente desde NodeSource..."
sudo apt-get remove -y nodejs libnode-dev || true
curl -fsSL https://deb.nodesource.com/setup_18.x | sudo -E bash -
sudo apt-get install -y nodejs

echo "📦 Instalando Yarn globalmente..."
sudo npm install -g yarn

# Verificaciones
echo "✅ Node.js instalado: $(node -v)"
echo "✅ npm instalado: $(npm -v)"
echo "✅ Yarn instalado: $(yarn -v)"

echo "🎉 Todas las dependencias fueron instaladas correctamente."
