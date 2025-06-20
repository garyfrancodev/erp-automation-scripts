#!/bin/bash
set -e

echo "📦 Instalando Node.js v18 con NVM..."

# Instalar NVM si no está instalado
if [ ! -d "$HOME/.nvm" ]; then
  curl -o- https://raw.githubusercontent.com/nvm-sh/nvm/v0.40.3/install.sh | bash
fi

# Cargar NVM en el entorno actual
export NVM_DIR="$HOME/.nvm"
# shellcheck disable=SC1090
[ -s "$NVM_DIR/nvm.sh" ] && source "$NVM_DIR/nvm.sh"

# Instalar y usar Node.js 18
nvm install 18
nvm alias default 18
nvm use 18

# Verificar instalación
echo "✅ Node instalado: $(node -v)"
echo "✅ NPM instalado:  $(npm -v)"
