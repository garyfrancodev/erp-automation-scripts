#!/bin/bash
source "$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)/core/lib.sh"

DB_USER="${DB_ROOT_USER:-frappe}"
DB_HOST="localhost"
FRAPPE_CNF_PATH="/etc/mysql/conf.d/frappe.cnf"

load_env
DB_USER="${DB_ROOT_USER:-$DB_USER}"

echo "🛢️ Instalando MariaDB..."
apt_get install -y mariadb-server mariadb-client
sudo systemctl enable mariadb

echo "🔐 Configurando seguridad de MariaDB..."
sudo mysql <<'SQL'
DELETE FROM mysql.user WHERE User='';
DROP DATABASE IF EXISTS test;
DELETE FROM mysql.db WHERE Db='test' OR Db='test\_%';
FLUSH PRIVILEGES;
SQL

# Nota: innodb_file_format e innodb_large_prefix se eliminaron en MariaDB 10.3+
# (Barracuda/large prefix son el comportamiento por defecto); incluirlos impide arrancar el servicio.
FRAPPE_CNF_CONTENT="[mysqld]
character-set-client-handshake = FALSE
character-set-server = utf8mb4
collation-server = utf8mb4_unicode_ci
innodb_file_per_table = 1
max_allowed_packet = 256M
wait_timeout = 28800
net_read_timeout = 36000
net_write_timeout = 36000"

if [ -n "$INNODB_BUFFER_POOL_SIZE" ]; then
  FRAPPE_CNF_CONTENT+="
innodb_buffer_pool_size = $INNODB_BUFFER_POOL_SIZE"
fi

FRAPPE_CNF_CONTENT+="

[mysql]
default-character-set = utf8mb4

[mysqldump]
max_allowed_packet = 256M"

sudo mkdir -p "$(dirname "$FRAPPE_CNF_PATH")"
if ! sudo test -f "$FRAPPE_CNF_PATH" || ! echo "$FRAPPE_CNF_CONTENT" | sudo diff -q "$FRAPPE_CNF_PATH" - >/dev/null; then
  echo "$FRAPPE_CNF_CONTENT" | sudo tee "$FRAPPE_CNF_PATH" >/dev/null
  echo "🔁 Reiniciando MariaDB por nueva configuración..."
  sudo systemctl restart mariadb
else
  echo "✅ Configuración ya aplicada. Sin reinicio."
fi

# Reutiliza la contraseña guardada en .env; solo genera una nueva si no existe.
if [ -z "${DB_ROOT_PASSWORD:-}" ]; then
  DB_ROOT_PASSWORD="$(gen_password)"
  echo "🔑 Generando contraseña nueva para '$DB_USER'."
else
  echo "🔑 Reutilizando la contraseña de '$DB_USER' guardada en $ENV_FILE."
fi

# El SQL va por stdin para que la contraseña no aparezca en la lista de procesos.
echo "👤 Configurando usuario '$DB_USER'..."
sudo mysql <<SQL
CREATE USER IF NOT EXISTS '$DB_USER'@'$DB_HOST' IDENTIFIED BY '$DB_ROOT_PASSWORD';
ALTER USER '$DB_USER'@'$DB_HOST' IDENTIFIED BY '$DB_ROOT_PASSWORD';
GRANT ALL PRIVILEGES ON *.* TO '$DB_USER'@'$DB_HOST' WITH GRANT OPTION;
FLUSH PRIVILEGES;
SQL

set_env DB_ROOT_USER "$DB_USER"
set_env DB_ROOT_PASSWORD "$DB_ROOT_PASSWORD"

echo "✅ MariaDB lista para usar con ERPNext."
echo "🔑 Usuario: $DB_USER"
echo "📝 Contraseña guardada en: $ENV_FILE (permisos 600). No se muestra en pantalla."
