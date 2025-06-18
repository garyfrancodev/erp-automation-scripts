#!/bin/bash
set -e

echo "🚀 Iniciando instalación paso a paso del entorno ERPNext..."

echo "1️⃣  Actualizando sistema..."
bash scripts/update-system.sh

echo "2️⃣  Creando usuario frappe..."
bash scripts/create-frappe-user.sh

echo "3️⃣  Instalando dependencias generales..."
bash scripts/install-dependencies.sh

echo "4️⃣  Instalando y configurando MariaDB..."
bash scripts/install-mariadb.sh

echo "5️⃣  Instalando Node.js y Yarn..."
bash scripts/install-node.sh

echo "✅ Instalación base completa. Ahora puedes continuar con Frappe Bench."
