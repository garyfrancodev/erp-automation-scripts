#!/bin/bash
source "$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)/core/lib.sh"

# ---------- Zona horaria ----------
echo "🕒 Zona horaria: $TIMEZONE"
sudo timedatectl set-timezone "$TIMEZONE"

# ---------- Swap (evita OOM en 'bench build' / 'yarn' en VPS pequeños) ----------
if [ -n "$SWAP_SIZE" ] && [ "$SWAP_SIZE" != "0" ]; then
  if [ -n "$(swapon --show --noheadings)" ]; then
    echo "✔️ Ya hay swap activo. Sin cambios."
  else
    echo "💾 Creando swap de $SWAP_SIZE en /swapfile..."
    if ! sudo fallocate -l "$SWAP_SIZE" /swapfile; then
      echo "⚠️  fallocate no soportado en este sistema de archivos; reintentando con dd..."
      SWAP_MB="$(numfmt --from=iec "$SWAP_SIZE" | awk '{printf "%d", $1/1048576}')"
      sudo dd if=/dev/zero of=/swapfile bs=1M count="$SWAP_MB" status=none
    fi
    sudo chmod 600 /swapfile
    sudo mkswap /swapfile >/dev/null
    sudo swapon /swapfile
    grep -q '^/swapfile ' /etc/fstab || echo '/swapfile none swap sw 0 0' | sudo tee -a /etc/fstab >/dev/null
    echo "✅ Swap activo."
  fi
fi

# ---------- Firewall ----------
if [ "$ENABLE_UFW" = "true" ]; then
  echo "🧱 Configurando firewall (ufw): SSH($SSH_PORT), 80, 443..."
  apt_get install -y ufw
  # Primero SSH, para no perder el acceso al activar el firewall.
  sudo ufw allow "$SSH_PORT/tcp"
  sudo ufw allow 80/tcp
  sudo ufw allow 443/tcp
  sudo ufw --force enable
else
  echo "⏭️  ENABLE_UFW != true: se omite el firewall."
fi

# ---------- Límites del sistema (Descriptores de archivos) ----------
echo "📈 Configurando límites de archivos abiertos (nofile) para '$FRAPPE_USER'..."
sudo tee "/etc/security/limits.d/${FRAPPE_USER}.conf" >/dev/null <<EOF
$FRAPPE_USER soft nofile 65535
$FRAPPE_USER hard nofile 65535
$FRAPPE_USER soft nproc 65535
$FRAPPE_USER hard nproc 65535
EOF

if [ ! -f /etc/sysctl.d/99-frappe.conf ]; then
  echo "fs.file-max = 2097152" | sudo tee /etc/sysctl.d/99-frappe.conf >/dev/null
  sudo sysctl -q -p /etc/sysctl.d/99-frappe.conf || true
fi

# ---------- Logrotate para Frappe Bench ----------
echo "🔄 Configurando rotación de logs (logrotate) para Frappe Bench..."
sudo tee "/etc/logrotate.d/frappe-bench" >/dev/null <<EOF
$BENCH_PATH/logs/*.log {
    weekly
    missingok
    rotate 4
    compress
    delaycompress
    notifempty
    copytruncate
    create 640 $FRAPPE_USER $FRAPPE_USER
}
EOF

echo "✅ Servidor base preparado."
