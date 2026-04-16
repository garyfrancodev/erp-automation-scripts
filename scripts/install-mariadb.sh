#!/bin/bash
#
# install-mariadb.sh - Instala y configura MariaDB para Frappe v15
# Requisitos: Ubuntu 22.04 LTS, ejecutado como root
#

set -euo pipefail
export DEBIAN_FRONTEND=noninteractive

# ----------------------------------------------------------------------
# Configuración
# ----------------------------------------------------------------------
ENV_FILE="/etc/frappe-automation/.env"
FRAPPE_CNF_PATH="/etc/mysql/mariadb.conf.d/99-frappe.cnf"

# ----------------------------------------------------------------------
# Verificar privilegios
# ----------------------------------------------------------------------
if [[ $EUID -ne 0 ]]; then
    echo "❌ Este script debe ejecutarse como root o con sudo." >&2
    exit 1
fi

# Log (sin exponer passwords — se loguea todo excepto las líneas sensibles)
LOG_FILE="/var/log/install-mariadb-$(date +%Y%m%d-%H%M%S).log"
exec > >(tee -a "$LOG_FILE") 2>&1

echo "📝 Log: $LOG_FILE"
echo "🕐 Inicio: $(date)"

# ----------------------------------------------------------------------
# 1. Instalar MariaDB
# ----------------------------------------------------------------------
echo "🛢️  [1/6] Instalando MariaDB..."
apt-get install -y mariadb-server mariadb-client

# Asegurar que está corriendo y habilitado al boot
systemctl enable --now mariadb

# ----------------------------------------------------------------------
# 2. Configurar MariaDB para Frappe v15
# ----------------------------------------------------------------------
echo "⚙️  [2/6] Escribiendo configuración optimizada para Frappe..."

# Calcular innodb_buffer_pool_size como 50% de RAM disponible (recomendado para DB-only servers es 70%,
# pero aquí corre también Frappe/Redis/Nginx, así que 30-40% es más seguro)
TOTAL_RAM_MB=$(free -m | awk '/^Mem:/{print $2}')
INNODB_BUFFER_POOL_MB=$((TOTAL_RAM_MB * 35 / 100))

# Escribir configuración
cat > "$FRAPPE_CNF_PATH" <<EOF
# Configuración para Frappe/ERPNext v15
# Generado el $(date)

[mysqld]
# --- Charset y collation (REQUERIDO por Frappe) ---
character-set-client-handshake = FALSE
character-set-server = utf8mb4
collation-server = utf8mb4_unicode_ci

# --- Bind address (solo localhost — nunca exponer al mundo) ---
bind-address = 127.0.0.1

# --- InnoDB (defaults modernos, sin opciones obsoletas) ---
innodb_file_per_table = 1
innodb_buffer_pool_size = ${INNODB_BUFFER_POOL_MB}M
innodb_log_file_size = 256M
innodb_flush_log_at_trx_commit = 1
innodb_flush_method = O_DIRECT

# --- Conexiones ---
max_connections = 500
max_allowed_packet = 256M

# --- Timeouts ---
wait_timeout = 600
interactive_timeout = 600

# --- Tablas temporales ---
tmp_table_size = 64M
max_heap_table_size = 64M

# --- Logging lento (útil para debugging de performance) ---
slow_query_log = 1
slow_query_log_file = /var/log/mysql/mariadb-slow.log
long_query_time = 2

[mysql]
default-character-set = utf8mb4

[client]
default-character-set = utf8mb4
EOF

chmod 644 "$FRAPPE_CNF_PATH"
echo "   ✅ Config escrita en $FRAPPE_CNF_PATH"
echo "   ℹ️  innodb_buffer_pool_size: ${INNODB_BUFFER_POOL_MB}M (RAM total: ${TOTAL_RAM_MB}M)"

# Reiniciar para aplicar
echo "🔁 Reiniciando MariaDB..."
systemctl restart mariadb
sleep 2

# Verificar que arrancó
if ! systemctl is-active --quiet mariadb; then
    echo "❌ MariaDB no arrancó correctamente. Revisa: journalctl -u mariadb" >&2
    exit 1
fi

# ----------------------------------------------------------------------
# 3. Configurar password de root (necesario para bench)
# ----------------------------------------------------------------------
echo "🔐 [3/6] Configurando password de root de MariaDB..."

# Verificar si ya hay password configurada leyendo del .env (idempotencia)
mkdir -p "$(dirname "$ENV_FILE")"
touch "$ENV_FILE"
chmod 600 "$ENV_FILE"

if grep -q "^MYSQL_ROOT_PASSWORD=" "$ENV_FILE"; then
    echo "   ℹ️  Password de root ya existe en $ENV_FILE (no se regenera)"
    MYSQL_ROOT_PASSWORD=$(grep "^MYSQL_ROOT_PASSWORD=" "$ENV_FILE" | cut -d= -f2-)
else
    # Generar password fuerte (32 caracteres alfanuméricos, sin símbolos que puedan romper shells)
    MYSQL_ROOT_PASSWORD=$(openssl rand -base64 32 | tr -d '/+=' | cut -c1-32)
    echo "MYSQL_ROOT_PASSWORD=${MYSQL_ROOT_PASSWORD}" >> "$ENV_FILE"
    echo "   ✅ Password de root generada y guardada en $ENV_FILE"
fi

# Aplicar password al usuario root — usando autenticación por socket (que sigue activa por default)
# Nota: mantenemos unix_socket también, para que 'sudo mysql' siga funcionando
mysql -u root <<EOF
ALTER USER 'root'@'localhost' IDENTIFIED VIA unix_socket OR mysql_native_password USING PASSWORD('${MYSQL_ROOT_PASSWORD}');
FLUSH PRIVILEGES;
EOF

echo "   ✅ Root puede autenticar con socket (sudo) O password (bench)"

# ----------------------------------------------------------------------
# 4. Hardening (equivalente a mysql_secure_installation)
# ----------------------------------------------------------------------
echo "🛡️  [4/6] Aplicando hardening de seguridad..."

mysql -u root <<EOF
-- Eliminar usuarios anónimos
DELETE FROM mysql.global_priv WHERE User='';

-- Eliminar acceso remoto de root (solo localhost)
DELETE FROM mysql.global_priv WHERE User='root' AND Host NOT IN ('localhost', '127.0.0.1', '::1');

-- Eliminar base de datos 'test' si existe
DROP DATABASE IF EXISTS test;
DELETE FROM mysql.db WHERE Db='test' OR Db='test\\_%';

-- Aplicar cambios
FLUSH PRIVILEGES;
EOF

echo "   ✅ Usuarios anónimos eliminados"
echo "   ✅ Acceso remoto de root deshabilitado"
echo "   ✅ Base de datos 'test' eliminada"

# ----------------------------------------------------------------------
# 5. Verificación final
# ----------------------------------------------------------------------
echo "🔍 [5/6] Verificando instalación..."

# Probar login con password
if mysql -u root -p"${MYSQL_ROOT_PASSWORD}" -e "SELECT VERSION();" > /dev/null 2>&1; then
    MARIADB_VERSION=$(mysql -u root -p"${MYSQL_ROOT_PASSWORD}" -NBe "SELECT VERSION();")
    echo "   ✅ Login con password: OK"
    echo "   ✅ Versión MariaDB: ${MARIADB_VERSION}"
else
    echo "   ❌ No se pudo autenticar root con password. Revisa la config." >&2
    exit 1
fi

# Probar login con socket
if mysql -u root -e "SELECT 1;" > /dev/null 2>&1; then
    echo "   ✅ Login con socket (sudo mysql): OK"
else
    echo "   ⚠️  Login con socket no funciona (no crítico si bench usa password)"
fi

# Verificar charset
CHARSET=$(mysql -u root -p"${MYSQL_ROOT_PASSWORD}" -NBe "SELECT @@character_set_server;")
if [[ "$CHARSET" == "utf8mb4" ]]; then
    echo "   ✅ Charset server: utf8mb4"
else
    echo "   ⚠️  Charset incorrecto: $CHARSET (esperado utf8mb4)" >&2
fi

# ----------------------------------------------------------------------
# 6. Resumen (sin exponer password en stdout)
# ----------------------------------------------------------------------
echo ""
echo "━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━"
echo "✅ MariaDB instalada y configurada para Frappe v15"
echo "━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━"
echo "  Versión:              ${MARIADB_VERSION}"
echo "  Config:               ${FRAPPE_CNF_PATH}"
echo "  Bind address:         127.0.0.1 (solo localhost)"
echo "  innodb_buffer_pool:   ${INNODB_BUFFER_POOL_MB}M"
echo "  Credenciales root:    ${ENV_FILE}"
echo "  Log slow queries:     /var/log/mysql/mariadb-slow.log"
echo "━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━"
echo ""
echo "🕐 Fin: $(date)"
echo ""
echo "ℹ️  NOTA: Frappe creará usuarios/DBs por sitio automáticamente con 'bench new-site'."
echo "   No es necesario crear un usuario 'frappe' global."
