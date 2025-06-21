#!/bin/bash
set -e

DB_USER="frappe"
DB_HOST="localhost"
ENV_FILE="/opt/erp-automation-scripts/.env"
FRAPPE_CNF_PATH="/etc/mysql/conf.d/frappe.cnf"

echo "🛢️ Instalando MariaDB..."
sudo apt-get install -y mariadb-server mariadb-client

echo "🔐 Configurando seguridad de MariaDB..."
sudo mysql -e "DELETE FROM mysql.user WHERE User='';"
sudo mysql -e "DROP DATABASE IF EXISTS test;"
sudo mysql -e "DELETE FROM mysql.db WHERE Db='test' OR Db='test\\_%';"
sudo mysql -e "FLUSH PRIVILEGES;"

FRAPPE_CNF_CONTENT="[mysqld]
character-set-client-handshake = FALSE
character-set-server = utf8mb4
collation-server = utf8mb4_unicode_ci
innodb_file_format = Barracuda
innodb_file_per_table = 1
innodb_large_prefix = 1"

if ! sudo test -f "$FRAPPE_CNF_PATH" || ! echo "$FRAPPE_CNF_CONTENT" | sudo diff -q "$FRAPPE_CNF_PATH" - >/dev/null; then
  echo "$FRAPPE_CNF_CONTENT" | sudo tee "$FRAPPE_CNF_PATH" > /dev/null
  echo "🔁 Reiniciando MariaDB por nueva configuración..."
  sudo systemctl restart mariadb
else
  echo "✅ Configuración ya aplicada. Sin reinicio."
fi

DB_PASSWORD=$(openssl rand -base64 12)
USER_EXISTS=$(sudo mysql -NBe "SELECT COUNT(*) FROM mysql.user WHERE user = '$DB_USER' AND host = '$DB_HOST';")

if [ "$USER_EXISTS" -eq 0 ]; then
  echo "👤 Creando usuario '$DB_USER'..."
  sudo mysql -e "CREATE USER '$DB_USER'@'$DB_HOST' IDENTIFIED BY '$DB_PASSWORD';"
else
  echo "🔄 Usuario '$DB_USER' ya existe. Se actualizará contraseña..."
  sudo mysql -e "ALTER USER '$DB_USER'@'$DB_HOST' IDENTIFIED BY '$DB_PASSWORD';"
fi

sudo mysql -e "GRANT ALL PRIVILEGES ON *.* TO '$DB_USER'@'$DB_HOST' WITH GRANT OPTION;"
sudo mysql -e "FLUSH PRIVILEGES;"

echo "✅ MariaDB lista para usar con ERPNext."
echo "🔑 Usuario: $DB_USER"
echo "🔐 Contraseña generada: $DB_PASSWORD"
echo "📝 Guardada también en: $ENV_FILE"
