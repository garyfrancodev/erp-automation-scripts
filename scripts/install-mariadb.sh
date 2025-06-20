#!/bin/bash
set -e

echo "🛢️ Instalando MariaDB..."
sudo apt-get install -y mariadb-server mariadb-client

echo "🔐 Ejecutando configuración segura..."
sudo mariadb-secure-installation

echo "🔧 Configurando charset y compatibilidad para Frappe..."
sudo tee /etc/mysql/conf.d/frappe.cnf > /dev/null <<EOF
[mysqld]
character-set-client-handshake = FALSE
character-set-server = utf8mb4
collation-server = utf8mb4_unicode_ci
innodb_file_format = Barracuda
innodb_file_per_table = 1
innodb_large_prefix = 1
EOF

echo "🔁 Reiniciando MariaDB..."
sudo systemctl restart mariadb

echo "✅ MariaDB instalado y configurado correctamente para ERPNext."
