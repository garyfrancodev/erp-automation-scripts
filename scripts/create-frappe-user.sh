#!/bin/bash
set -e

USERNAME="frappe"
PROJECT_DIR="/opt/erp-automation-scripts"
ENV_FILE="$PROJECT_DIR/.env"

# Verificar si el usuario ya existe
if id "$USERNAME" &>/dev/null; then
    echo "⚠️  El usuario '$USERNAME' ya existe. No se creará de nuevo."
else
    echo "👤 Creando usuario '$USERNAME'..."

    # Crear usuario sin contraseña
    sudo adduser --gecos "" --disabled-password "$USERNAME"

    # Generar contraseña segura
    PASSWORD=$(openssl rand -base64 12)

    # Asignar la contraseña al usuario
    echo "$USERNAME:$PASSWORD" | sudo chpasswd

    # Agregar al grupo sudo
    sudo usermod -aG sudo "$USERNAME"

    echo "✅ Usuario '$USERNAME' creado correctamente."
    echo "🔑 Contraseña generada: $PASSWORD"
    echo "📌 IMPORTANTE: Guarda esta contraseña en un lugar seguro."

    # Guardar en .env si existe el directorio
    if [ -d "$PROJECT_DIR" ]; then
        echo "📁 Ajustando permisos para $PROJECT_DIR..."
        sudo chown -R "$USERNAME:$USERNAME" "$PROJECT_DIR"

        echo "📝 Guardando contraseña en $ENV_FILE..."
        echo "FRAPPE_USER=$USERNAME" > "$ENV_FILE"
        echo "FRAPPE_PASSWORD=$PASSWORD" >> "$ENV_FILE"
        chmod 600 "$ENV_FILE"
    fi
fi
