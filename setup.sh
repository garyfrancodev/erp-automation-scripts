#!/bin/bash
set -Eeuo pipefail

# Uso (desde la raíz del repo, con un usuario con sudo, p. ej. root):
#   bash setup.sh
#
# Orden completo de instalación:
#   1) bash setup.sh                                             → prepara el servidor (este script)
#   2) su - frappe                                               → cambiar al usuario frappe
#   3) bash scripts/02-bench-setup/01-install-frappe.sh          → crea el bench
#   4) bash scripts/02-bench-setup/02-install-apps.sh            → descarga erpnext, hrms, webshop
#   5) bash scripts/02-bench-setup/03-setup-production.sh        → nginx + supervisor + multisitio
#   6) bash scripts/sites/create-site.sh <subdominio>            → crea un sitio (por cliente)
#   7) bash scripts/sites/enable-ssl.sh <sitio> <correo>         → SSL cuando el DNS propague

CURRENT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"

# Si el repositorio fue clonado dentro de /root, el usuario 'frappe' no podrá acceder por permisos.
# Se migra automáticamente a /opt/erp-automation-scripts para garantizar transparencia total.
if [[ "$CURRENT_DIR" == /root* ]]; then
  TARGET_OPT="/opt/erp-automation-scripts"
  echo "⚠️  Detectado repositorio dentro de /root ($CURRENT_DIR)."
  echo "    El usuario 'frappe' no tiene acceso a /root. Moviendo a $TARGET_OPT..."
  sudo mkdir -p /opt
  sudo mv "$CURRENT_DIR" "$TARGET_OPT"
  cd "$TARGET_OPT"
  exec bash "$TARGET_OPT/setup.sh"
fi

SCRIPTS_DIR="$CURRENT_DIR/scripts"
SERVER_DIR="$SCRIPTS_DIR/01-server-setup"

echo "🚀 Iniciando instalación paso a paso del servidor base..."

echo "1️⃣  Actualizando sistema..."
bash "$SERVER_DIR/01-update-system.sh"

echo "2️⃣  Creando usuario frappe..."
bash "$SERVER_DIR/02-create-frappe-user.sh"

echo "3️⃣  Preparando servidor (zona horaria, swap, firewall)..."
bash "$SERVER_DIR/03-prepare-server.sh"

echo "4️⃣  Instalando dependencias generales (incluye Node.js y Yarn)..."
bash "$SERVER_DIR/04-install-dependencies.sh"

echo "5️⃣  Instalando y configurando MariaDB..."
bash "$SERVER_DIR/05-install-mariadb.sh"

echo "✅ Instalación base del servidor completa."
echo ""
echo "➡️  Siguientes pasos (como usuario frappe):"
echo "   1. su - frappe"
echo "   2. cd $(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
echo "   3. bash scripts/02-bench-setup/01-install-frappe.sh"
echo "   4. bash scripts/02-bench-setup/02-install-apps.sh"
echo "   5. bash scripts/02-bench-setup/03-setup-production.sh"
