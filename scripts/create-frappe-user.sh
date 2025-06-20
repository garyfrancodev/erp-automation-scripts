#!/bin/bash
set -e

USERNAME="frappe"

# Verificar si el usuario ya existe
if id "$USERNAME" &>/dev/null; then
    echo "⚠️  El usuario '$USERNAME' ya existe. No se creará de nuevo."
else
    echo "👤 Creando usuario '$USERNAME'..."

    # Crear usuario sin contraseña
    sudo adduser --gecos "" --disabled-password "$USERNAME"

    # Generar una contraseña segura de 12 caracteres
    PASSWORD=$(openssl rand -base64 12)

    # Asignar la contraseña al usuario
    echo "$USERNAME:$PASSWORD" | sudo chpasswd

    # Agregar al grupo sudo
    sudo usermod -aG sudo "$USERNAME"

    # Asignar permisos al directorio del proyecto
    sudo chown -R "$USERNAME:$USERNAME" /opt/erp-automation-scripts

    echo "✅ Usuario '$USERNAME' creado correctamente."
    echo "🔑 Contraseña generada: $PASSWORD"
    echo "📌 IMPORTANTE: Guarda esta contraseña en un lugar seguro."
fi
