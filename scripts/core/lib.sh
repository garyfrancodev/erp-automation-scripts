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
