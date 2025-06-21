#!/bin/bash
set -e

echo "📦 Instalando Node.js v18 con NVM..."

# Asegurar que no se ejecute como root
if [ "$(whoami)" = "root" ]; then
  echo "❌ Este script debe ejecutarse como el usuario 'frappe', no como root."
  echo "🔁 Usa: su - frappe"
  exit 1
fi

# Verificar si ya está instalado
if command -v node >/dev/null 2>&1 && node -v | grep -q "v18"; then
  echo "✅ Node.js ya está instalado: $(node -v)"
  exit 0
fi

# Instalar NVM si no existe
if [ ! -d "$HOME/.nvm" ]; then
  echo "🔧 Instalando NVM..."
  curl -o- https://raw.githubusercontent.com/nvm-sh/nvm/v0.40.3/install.sh | bash
fi

# Cargar NVM
export NVM_DIR="$HOME/.nvm"
# shellcheck disable=SC1090
[ -s "$NVM_DIR/nvm.sh" ] && source "$NVM_DIR/nvm.sh"

# Instalar Node.js v18 y establecer como default
nvm install 18
nvm alias default 18
nvm use 18

# Agregar configuración a bashrc para futuras sesiones
echo 'export NVM_DIR="$HOME/.nvm"' >> "$HOME/.bashrc"
echo '[ -s "$NVM_DIR/nvm.sh" ] && \. "$NVM_DIR/nvm.sh"' >> "$HOME/.bashrc"

# Verificar
echo "✅ Node instalado: $(node -v)"
echo "✅ NPM instalado:  $(npm -v)"
