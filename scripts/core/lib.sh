#!/bin/bash
# ============================================================
# Funciones comunes. Se usa con:  source "<ruta>/lib.sh"
# ============================================================
set -Eeuo pipefail
trap 'echo "❌ Error en $(basename "$0") (línea $LINENO)" >&2' ERR

LIB_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
ROOT_DIR="$(cd "$LIB_DIR/../.." && pwd)"

# shellcheck source=config.env
source "$LIB_DIR/config.env"

# Autodetección de la IP pública del servidor si no está definida
get_public_ip() {
  local ip=""
  ip="$(curl -s4 --max-time 3 https://ifconfig.me 2>/dev/null \
     || curl -s4 --max-time 3 https://api.ipify.org 2>/dev/null \
     || ip route get 1.1.1.1 2>/dev/null | awk '{print $7; exit}' \
     || true)"
  echo "${ip:-127.0.0.1}"
}
SERVER_IP="${SERVER_IP:-$(get_public_ip)}"

ENV_FILE="${ENV_FILE:-$ROOT_DIR/.env}"
FRAPPE_HOME="/home/$FRAPPE_USER"
BENCH_PATH="$FRAPPE_HOME/$BENCH_NAME"

# ---------- Utilidades ----------

# apt-get no interactivo (la variable debe pasar a través de sudo).
apt_get() {
  sudo env DEBIAN_FRONTEND=noninteractive NEEDRESTART_MODE=a apt-get "$@"
}

# Contraseña aleatoria apta para shell/SQL/URL (solo hexadecimal). Longitud por defecto: 32.
gen_password() {
  openssl rand -hex "$(( ${1:-32} / 2 ))"
}

# Ejecuta un comando como el usuario frappe (o directo si ya lo somos).
as_frappe() {
  if [ "$(id -un)" = "$FRAPPE_USER" ]; then
    "$@"
  else
    sudo -u "$FRAPPE_USER" -H "$@"
  fi
}

require_cmd() {
  command -v "$1" &>/dev/null || { echo "❌ Falta el comando '$1'. ${2:-}" >&2; exit 1; }
}

require_user() {
  if [ "$(id -un)" != "$1" ]; then
    echo "❌ Este script debe ejecutarse como el usuario '$1' (ahora: $(id -un))." >&2
    exit 1
  fi
}

require_bench() {
  require_cmd bench "Ejecuta primero scripts/02-bench-setup/01-install-frappe.sh"
  if [ ! -f "$BENCH_PATH/Procfile" ]; then
    echo "❌ '$BENCH_PATH' no parece un bench válido." >&2
    exit 1
  fi
}

# ---------- Manejo del archivo .env (secretos) ----------

# Carga el .env si existe y es legible (con sudo si hace falta).
load_env() {
  [ -n "$(sudo find "$ENV_FILE" -maxdepth 0 2>/dev/null)" ] || return 0
  set -a
  # shellcheck disable=SC1090
  source <(sudo cat "$ENV_FILE")
  set +a
}

# set_env CLAVE VALOR → crea o actualiza una variable sin tocar las demás.
# El archivo queda con permisos 600 y propiedad del usuario frappe (si existe).
set_env() {
  local key="$1" value="$2"
  sudo mkdir -p "$(dirname "$ENV_FILE")"
  sudo touch "$ENV_FILE"
  sudo chmod 600 "$ENV_FILE"
  sudo sed -i "/^${key}=/d" "$ENV_FILE"
  printf '%s=%s\n' "$key" "$value" | sudo tee -a "$ENV_FILE" >/dev/null
  if id "$FRAPPE_USER" &>/dev/null; then
    sudo chown "$FRAPPE_USER:$FRAPPE_USER" "$ENV_FILE"
  fi
}

# ---------- Servicios de Background (Supervisor & Redis) ----------

ensure_redis_and_supervisor() {
  echo "🔍 Verificando servicios de background (Supervisor y Redis)..."

  # Asegurar que el demonio de Supervisor esté activo en systemd
  if ! sudo systemctl is-active --quiet supervisor; then
    echo "⚙️ Iniciando demonio de Supervisor..."
    sudo systemctl enable --now supervisor
    sudo systemctl restart supervisor
    sleep 2
  fi

  # Asegurar que la configuración de supervisor para el bench exista
  if [ -f "$BENCH_PATH/config/supervisor.conf" ] && [ ! -f /etc/supervisor/conf.d/frappe-bench.conf ]; then
    echo "🔗 Vinculando configuración de Supervisor para Frappe Bench..."
    sudo ln -sf "$BENCH_PATH/config/supervisor.conf" /etc/supervisor/conf.d/frappe-bench.conf
    sudo supervisorctl reread 2>/dev/null || true
    sudo supervisorctl update 2>/dev/null || true
  fi

  # Recargar configuración y arrancar procesos de Frappe si estaban detenidos
  sudo supervisorctl reread 2>/dev/null || true
  sudo supervisorctl update 2>/dev/null || true
  sudo supervisorctl start all 2>/dev/null || true

  # Verificar si Redis Queue (11000) responde; reintentar hasta 8 veces
  local max_retries=8
  local count=0
  while ! redis-cli -p 11000 ping &>/dev/null; do
    count=$((count + 1))
    if [ "$count" -ge "$max_retries" ]; then
      echo "⚠️ Redis Queue (puerto 11000) no respondió vía Supervisor."
      echo "   Iniciando Redis Queue en modo demonio de contingencia..."
      if [ -f "$BENCH_PATH/config/redis_queue.conf" ]; then
        redis-server "$BENCH_PATH/config/redis_queue.conf" --daemonize yes 2>/dev/null || true
      fi
      if [ -f "$BENCH_PATH/config/redis_cache.conf" ]; then
        redis-server "$BENCH_PATH/config/redis_cache.conf" --daemonize yes 2>/dev/null || true
      fi
      sleep 2
      break
    fi
    echo "⏳ Esperando disponibilidad de Redis Queue en 127.0.0.1:11000 (intento $count/$max_retries)..."
    sudo supervisorctl restart frappe-bench-redis:* 2>/dev/null || sudo supervisorctl start all 2>/dev/null || true
    sleep 1
  done

  if redis-cli -p 11000 ping &>/dev/null; then
    echo "✅ Redis Queue operativo en 127.0.0.1:11000."
  else
    echo "❌ No se pudo conectar a Redis Queue en 127.0.0.1:11000." >&2
    echo "   Revisa el estado con: sudo supervisorctl status" >&2
    exit 1
  fi
}

# ---------- Formato de Logs de Nginx ----------

ensure_nginx_log_format() {
  # En Ubuntu/Debian, Nginx no incluye el formato 'main' por defecto y Frappe Bench lo referencia en los virtual hosts.
  # Lo definimos en /etc/nginx/conf.d/00-frappe-log-format.conf para que cargue antes de frappe-bench.conf.
  if ! sudo grep -rn "log_format.*main" /etc/nginx/ 2>/dev/null | grep -v "conf.d/frappe-bench.conf" &>/dev/null; then
    echo "🔧 Configurando formato de log 'main' en Nginx..."
    sudo tee /etc/nginx/conf.d/00-frappe-log-format.conf >/dev/null <<'EOF'
log_format main '$remote_addr - $remote_user [$time_local] "$request" '
                '$status $body_bytes_sent "$http_referer" '
                '"$http_user_agent" "$http_x_forwarded_for"';
EOF
  fi
}


