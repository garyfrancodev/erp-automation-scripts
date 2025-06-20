#!/bin/bash
set -e

DB_USER="frappe"
DB_HOST="localhost"
ENV_FILE="/opt/erp-automation-scripts/.env"

echo "🛢️ Instalando MariaDB..."
sudo apt-get install -y mariadb-server mariadb-client

echo "🔐 Configurando seguridad de MariaDB (modo no interactivo)..."
sudo mysql -e "DELETE FROM mysql.user WHERE User='';"
sudo mysql -e "DROP DATABASE IF EXISTS test;"
sudo mysql -e "DELETE FROM mysql.db WHERE Db='test' OR Db='test\\_%';"
sudo mysql -e "FLUSH PRIVILEGES;"

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

echo "👤 Creando usuario MariaDB '$DB_USER' con contraseña aleatoria..."
DB_PASSWORD=$(openssl rand -base64 12)

sudo mysql -e "CREATE USER IF NOT EXISTS '$DB_USER'@'$DB_HOST' IDENTIFIED BY '$DB_PASSWORD';"
sudo mysql -e "GRANT ALL PRIVILEGES ON *.* TO '$DB_USER'@'$DB_HOST' WITH GRANT OPTION;"
sudo mysql -e "FLUSH PRIVILEGES;"

echo "📁 Guardando contraseña en $ENV_FILE..."
echo "DB_USER=$DB_USER" > "$ENV_FILE"
echo "DB_PASSWORD=$DB_PASSWORD" >> "$ENV_FILE"

chmod 600 "$ENV_FILE"

echo
echo "✅ MariaDB instalado y configurado correctamente para ERPNext."
echo "🔑 Usuario creado: $DB_USER"
echo "🔐 Contraseña generada: $DB_PASSWORD"
echo "📝 Guardada en: $ENV_FILE"
