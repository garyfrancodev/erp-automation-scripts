#!/bin/bash
source "$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)/core/lib.sh"

ARCH="$(dpkg --print-architecture)"

echo "📦 Instalando dependencias del sistema..."
apt_get update

apt_get install -y \
  git \
  python-is-python3 \
  python3-dev \
  python3-pip \
  python3-setuptools \
  python3-venv \
  pipx \
  fontconfig \
  libxrender1 \
  xfonts-75dpi \
  xfonts-base \
  redis-server \
  software-properties-common \
  build-essential \
  pkg-config \
  libffi-dev \
  libssl-dev \
  libmariadb-dev \
  jq \
  dnsutils \
  wget \
  gnupg \
  certbot \
  python3-certbot-nginx \
  nginx \
  supervisor \
  fail2ban \
  cron \
  curl \
  ca-certificates

# Frappe Bench administra sus propias instancias de Redis en puertos/sockets dedicados.
# Desactivamos el demonio predeterminado del sistema (puerto 6379) para no desperdiciar RAM.
if sudo systemctl is-active --quiet redis-server 2>/dev/null || sudo systemctl is-enabled --quiet redis-server 2>/dev/null; then
  echo "🛑 Desactivando redis-server del sistema (Bench gestiona sus propias instancias)..."
  sudo systemctl disable --now redis-server || true
fi

# ---------- Node.js ----------
if command -v node &>/dev/null && [[ "$(node -v)" == v${NODE_MAJOR}.* ]]; then
  echo "✔️ Node.js $(node -v) ya instalado."
else
  echo "🧼 Eliminando versiones conflictivas de Node.js..."
  apt_get remove --purge -y nodejs npm libnode72 libnode-dev nodejs-doc || true
  apt_get autoremove -y

  echo "📦 Instalando Node.js ${NODE_MAJOR}.x desde NodeSource..."
  curl -fsSL "https://deb.nodesource.com/setup_${NODE_MAJOR}.x" | sudo -E bash -
  apt_get install -y nodejs
fi
echo "✅ Node.js instalado: $(node -v)"
echo "✅ npm instalado: $(npm -v)"

if command -v yarn &>/dev/null; then
  echo "✔️ Yarn $(yarn -v) ya instalado."
else
  echo "📦 Instalando Yarn globalmente..."
  sudo npm install -g yarn
fi

# ---------- Ansible (bench setup production lo exige) ----------
if command -v ansible &>/dev/null; then
  echo "✔️ Ansible ya instalado."
else
  echo "📦 Instalando Ansible..."
  # Intentar primero desde repositorios nativos (en Ubuntu 24.04 ya está incluido)
  if ! apt_get install -y ansible 2>/dev/null; then
    echo "ℹ️ Agregando PPA para Ansible..."
    sudo add-apt-repository --yes --update ppa:ansible/ansible || true
    apt_get install -y ansible
  fi
fi

# ---------- wkhtmltopdf (versión con Qt parcheado) ----------
if command -v wkhtmltopdf &>/dev/null && wkhtmltopdf --version | grep -q "0.12.6.1"; then
  echo "✔️ wkhtmltopdf 0.12.6.1 ya instalado."
else
  echo "🖨️ Instalando wkhtmltopdf 0.12.6.1..."
  CODENAME="$(. /etc/os-release && echo "${VERSION_CODENAME:-}")"
  case "$CODENAME" in
    focal|jammy|bullseye|bookworm) ;;
    *)
      echo "⚠️  No hay paquete nativo de wkhtmltopdf para '$CODENAME'; se usa el de 'jammy'."
      CODENAME="jammy"
      ;;
  esac
  WKHTML_DEB="wkhtmltox_0.12.6.1-2.${CODENAME}_${ARCH}.deb"
  WKHTML_URL="https://github.com/wkhtmltopdf/packaging/releases/download/0.12.6.1-2/${WKHTML_DEB}"
  WKHTML_TMP="$(mktemp -d)"

  # En Ubuntu 24.04 (noble) o versiones sin libssl1.1, wkhtmltox lo requiere:
  if ! dpkg -s libssl1.1 &>/dev/null; then
    LIBSSL_URL=""
    if [ "$ARCH" = "amd64" ]; then
      LIBSSL_URL="http://archive.ubuntu.com/ubuntu/pool/main/o/openssl/libssl1.1_1.1.1f-1ubuntu2_amd64.deb"
    elif [ "$ARCH" = "arm64" ]; then
      LIBSSL_URL="http://ports.ubuntu.com/ubuntu-ports/pool/main/o/openssl/libssl1.1_1.1.1f-1ubuntu2_arm64.deb"
    fi
    if [ -n "$LIBSSL_URL" ]; then
      echo "📦 Descargando paquete de compatibilidad libssl1.1..."
      if wget -q "$LIBSSL_URL" -O "$WKHTML_TMP/libssl1.1.deb"; then
        sudo dpkg -i "$WKHTML_TMP/libssl1.1.deb" || apt_get install -f -y || true
      fi
    fi
  fi

  wget -q --show-progress "$WKHTML_URL" -O "$WKHTML_TMP/$WKHTML_DEB"
  sudo dpkg -i "$WKHTML_TMP/$WKHTML_DEB" || apt_get install -f -y
  rm -rf "$WKHTML_TMP"
fi

# ---------- 1Password CLI ----------
if command -v op &>/dev/null; then
  echo "✔️ 1Password CLI ya instalado."
else
  echo "🔐 Instalando 1Password CLI (op)..."
  curl -fsS https://downloads.1password.com/linux/keys/1password.asc \
    | sudo gpg --batch --yes --dearmor -o /usr/share/keyrings/1password-archive-keyring.gpg
  echo "deb [arch=${ARCH} signed-by=/usr/share/keyrings/1password-archive-keyring.gpg] https://downloads.1password.com/linux/debian/${ARCH} stable main" \
    | sudo tee /etc/apt/sources.list.d/1password.list >/dev/null
  apt_get update
fi

# ---------- Fail2ban (Protección de fuerza bruta para Frappe y Nginx) ----------
if command -v fail2ban-client &>/dev/null; then
  echo "🛡️ Configurando reglas de Fail2ban para Frappe/ERPNext..."
  sudo mkdir -p /etc/fail2ban/filter.d /etc/fail2ban/jail.d

  # Filtro contra intentos repetidos de inicio de sesión fallidos
  sudo tee /etc/fail2ban/filter.d/frappe-login.conf >/dev/null <<'EOF'
[Definition]
failregex = ^<HOST> -.* "(POST /api/method/login|POST /login) HTTP/.*" (401|403)
ignoreregex =
EOF

  # Cárcel activa para puertos web
  sudo tee /etc/fail2ban/jail.d/frappe.local >/dev/null <<EOF
[frappe-login]
enabled = true
port = http,https
filter = frappe-login
logpath = /var/log/nginx/*access.log
maxretry = 5
findtime = 600
bantime = 86400
EOF

  sudo systemctl restart fail2ban || true
  sudo systemctl enable fail2ban || true
  echo "✅ Fail2ban activo para Frappe."
fi

echo "✅ Dependencias del sistema instaladas correctamente."
