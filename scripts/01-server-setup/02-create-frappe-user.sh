#!/bin/bash
source "$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)/core/lib.sh"

if id "$FRAPPE_USER" &>/dev/null; then
  echo "⚠️  El usuario '$FRAPPE_USER' ya existe. No se creará de nuevo."
else
  echo "👤 Creando usuario '$FRAPPE_USER'..."
  sudo adduser --gecos "" --disabled-password "$FRAPPE_USER"

  PASSWORD="$(gen_password)"
  echo "$FRAPPE_USER:$PASSWORD" | sudo chpasswd
  sudo usermod -aG sudo "$FRAPPE_USER"

  set_env FRAPPE_USER "$FRAPPE_USER"
  set_env FRAPPE_PASSWORD "$PASSWORD"

  echo "✅ Usuario '$FRAPPE_USER' creado correctamente."
  echo "🔑 La contraseña se guardó en $ENV_FILE (permisos 600). No se muestra en pantalla."
  echo "   Consúltala con: sudo grep FRAPPE_PASSWORD $ENV_FILE"
fi

# Configurar sudo sin contraseña (necesario para bench setup production, certbot y recarga de nginx)
echo "🔑 Configurando privilegios sudo sin contraseña para '$FRAPPE_USER'..."
echo "$FRAPPE_USER ALL=(ALL) NOPASSWD:ALL" | sudo tee "/etc/sudoers.d/$FRAPPE_USER" >/dev/null
sudo chmod 440 "/etc/sudoers.d/$FRAPPE_USER"

# nginx (www-data) necesita poder atravesar /home/frappe para servir los assets.
echo "🔓 Permitiendo a nginx atravesar $FRAPPE_HOME..."
sudo chmod o+x "$FRAPPE_HOME"

# Evitar advertencias de Git sobre 'dubious ownership' al clonar/actualizar apps
as_frappe git config --global --add safe.directory "*"
