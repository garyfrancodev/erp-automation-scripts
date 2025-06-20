#!/bin/bash
set -e

echo "🛢️ Instalando MariaDB..."
sudo apt-get install -y mariadb-server mariadb-client

echo "🔐 Ejecutando configuración segura..."
sudo mariadb-secure-installation

echo "🔧 Configurando charset en /etc/mysql/my.cnf..."
sudo tee /etc/mysql/my.cnf > /dev/null <<EOF
[mysqld]
character-set-client-handshake = FALSE
character-set-server = utf8mb4
collation-server = utf8mb4_unicode_ci

[mysql]
default-character-set = utf8mb4
EOF
