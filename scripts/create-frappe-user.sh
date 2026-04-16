#!/bin/bash
#
# create-frappe-user.sh - Crea el usuario 'frappe' con permisos sudo granulares
# Requisitos: Ubuntu 22.04 LTS, ejecutado como root
#

set -euo pipefail

# ----------------------------------------------------------------------
# Configuración
# ----------------------------------------------------------------------
USERNAME="frappe"
USER_HOME="/home/${USERNAME}"
ENV_FILE="/etc/frappe-automation/.env"
SUDOERS_FILE="/etc/sudoers.d/frappe-limited"

# ----------------------------------------------------------------------
# Validaciones
# ----------------------------------------------------------------------
if [[ $EUID -ne 0 ]]; then
    echo "❌ Este script debe ejecutarse como root o con sudo." >&2
    exit 1
fi

# Log
LOG_FILE="/var/log/create-frappe-user-$(date +%Y%m%d-%H%M%S).log"
exec > >(tee -a "$LOG_FILE") 2>&1

echo "📝 Log: $LOG_FILE"
echo "🕐 Inicio: $(date)"

# ----------------------------------------------------------------------
# 1. Crear usuario (si no existe)
# ----------------------------------------------------------------------

echo "👤 [1/5] Creando usuario '${USERNAME}'..."

USER_CREATED=false
if id "${USERNAME}" &>/dev/null; then
    echo "   ℹ️  El usuario '${USERNAME}' ya existe"

    # Validar que tenga home y shell correctos
    CURRENT_HOME=$(getent passwd "${USERNAME}" | cut -d: -f6)
    CURRENT_SHELL=$(getent passwd "${USERNAME}" | cut -d: -f7)

    if [[ "${CURRENT_HOME}" != "${USER_HOME}" ]]; then
        echo "   ⚠️  Home incorrecto: ${CURRENT_HOME} (esperado: ${USER_HOME})" >&2
    fi

    if [[ ! -d "${CURRENT_HOME}" ]]; then
        echo "   ⚠️  El home ${CURRENT_HOME} no existe, creándolo..."
        mkdir -p "${CURRENT_HOME}"
        chown "${USERNAME}:${USERNAME}" "${CURRENT_HOME}"
    fi

    if [[ "${CURRENT_SHELL}" == "/usr/sbin/nologin" ]] || [[ "${CURRENT_SHELL}" == "/bin/false" ]]; then
        echo "   ⚠️  Shell deshabilitado, cambiando a /bin/bash..."
        usermod -s /bin/bash "${USERNAME}"
    fi
else
    # Crear usuario con home y shell bash, sin password inicial
    adduser \
        --gecos "Frappe Framework User" \
        --disabled-password \
        --shell /bin/bash \
        "${USERNAME}"

    USER_CREATED=true
    echo "   ✅ Usuario '${USERNAME}' creado"
fi

# ----------------------------------------------------------------------
# 2. Configurar password (solo si el usuario es nuevo)
# ----------------------------------------------------------------------

echo "🔐 [2/5] Configurando credenciales..."

# Preparar directorio del .env
mkdir -p "$(dirname "${ENV_FILE}")"
chmod 700 "$(dirname "${ENV_FILE}")"

if [[ -f "${ENV_FILE}" ]]; then
    chmod 600 "${ENV_FILE}"
fi

if [[ "${USER_CREATED}" == "true" ]]; then
    # Generar password fuerte (32 caracteres alfanuméricos)
    USER_PASSWORD=$(openssl rand -base64 48 | tr -d '/+=' | cut -c1-32)

    # Asignar password al usuario
    echo "${USERNAME}:${USERPASSWORD}" | chpasswd 2>/dev/null || echo "${USERNAME}:${USER_PASSWORD}" | chpasswd

    # Guardar en .env SIN sobrescribir variables existentes
    touch "${ENV_FILE}"
    chmod 600 "${ENV_FILE}"

    # Eliminar entradas previas de FRAPPE_USER/FRAPPE_PASSWORD si existieran
    sed -i '/^FRAPPE_USER=/d' "${ENV_FILE}"
    sed -i '/^FRAPPE_PASSWORD=/d' "${ENV_FILE}"

    # Agregar las nuevas (sin borrar otras variables como MYSQL_ROOT_PASSWORD)
    {
        echo "FRAPPE_USER=${USERNAME}"
        echo "FRAPPE_PASSWORD=${USER_PASSWORD}"
    } >> "${ENV_FILE}"

    echo "   ✅ Password generada y guardada en ${ENV_FILE}"
else
    echo "   ℹ️  Usuario existente — password no se regenera"
fi

# ----------------------------------------------------------------------
# 3. Configurar estructura del home
# ----------------------------------------------------------------------

echo "📁 [3/5] Configurando estructura del home..."

# Directorios necesarios para operar bench y SSH
sudo -u "${USERNAME}" mkdir -p \
    "${USER_HOME}/.local/bin" \
    "${USER_HOME}/.ssh" \
    "${USER_HOME}/logs" \
    "${USER_HOME}/backups"

# Permisos correctos para .ssh
chmod 700 "${USER_HOME}/.ssh"
touch "${USER_HOME}/.ssh/authorized_keys"
chmod 600 "${USER_HOME}/.ssh/authorized_keys"
chown -R "${USERNAME}:${USERNAME}" "${USER_HOME}/.ssh"

# Permisos del home (necesario para Nginx — recuerda que www-data lee assets)
chmod 755 "${USER_HOME}"

# Agregar ~/.local/bin al PATH si no está ya
if ! sudo -u "${USERNAME}" grep -q 'HOME/.local/bin' "${USER_HOME}/.bashrc" 2>/dev/null; then
    sudo -u "${USERNAME}" bash -c "echo 'export PATH=\"\$HOME/.local/bin:\$PATH\"' >> ${USER_HOME}/.bashrc"
    echo "   ✅ PATH actualizado en .bashrc"
fi

echo "   ✅ Estructura de home configurada"

# ----------------------------------------------------------------------
# 4. Configurar sudo GRANULAR (no grupo sudo completo)
# ----------------------------------------------------------------------

echo "🛡️  [4/5] Configurando permisos sudo granulares..."

# Solo permitir comandos específicos que bench necesita para operaciones administrativas
# NOTA: NO se añade al grupo 'sudo' — solo se permiten comandos específicos vía sudoers.d
cat > "${SUDOERS_FILE}" <<EOF
# Permisos granulares para el usuario 'frappe'
# NO es miembro del grupo sudo — solo puede ejecutar estos comandos específicos

# Gestión de servicios (para 'bench setup production' y reinicios)
${USERNAME} ALL=(ALL) NOPASSWD: /bin/systemctl restart nginx
${USERNAME} ALL=(ALL) NOPASSWD: /bin/systemctl reload nginx
${USERNAME} ALL=(ALL) NOPASSWD: /bin/systemctl status nginx
${USERNAME} ALL=(ALL) NOPASSWD: /bin/systemctl restart supervisor
${USERNAME} ALL=(ALL) NOPASSWD: /bin/systemctl reload supervisor
${USERNAME} ALL=(ALL) NOPASSWD: /bin/systemctl status supervisor
${USERNAME} ALL=(ALL) NOPASSWD: /usr/bin/supervisorctl *

# Comando bench con sudo (necesario para 'bench setup production' y 'bench setup nginx')
${USERNAME} ALL=(ALL) NOPASSWD: /home/${USERNAME}/.local/bin/bench
${USERNAME} ALL=(ALL) NOPASSWD: /home/${USERNAME}/.bench-venv/bin/bench

# Certbot (para renovación SSL)
${USERNAME} ALL=(ALL) NOPASSWD: /usr/bin/certbot
${USERNAME} ALL=(ALL) NOPASSWD: /snap/bin/certbot
EOF

# Validar sintaxis del sudoers (si hay error, no guardar)
if ! visudo -c -f "${SUDOERS_FILE}" > /dev/null; then
    echo "❌ Error de sintaxis en ${SUDOERS_FILE}. Abortando." >&2
    rm -f "${SUDOERS_FILE}"
    exit 1
fi

chmod 440 "${SUDOERS_FILE}"
echo "   ✅ Permisos sudo granulares configurados en ${SUDOERS_FILE}"

# Validar que el usuario NO está en el grupo sudo (por si había estado antes)
if groups "${USERNAME}" | grep -qw sudo; then
    echo "   ⚠️  Removiendo '${USERNAME}' del grupo 'sudo' (tiene permisos granulares)"
    deluser "${USERNAME}" sudo
fi

# ----------------------------------------------------------------------
# 5. Ajustar ownership de directorios relacionados
# ----------------------------------------------------------------------

echo "🔧 [5/5] Ajustando ownership de directorios..."

# IMPORTANTE: NO cambiar ownership del repo de scripts a 'frappe'
# El repo debe seguir siendo de root para que 'frappe' no pueda modificarlo
# (principio de mínimo privilegio)

# Solo nos aseguramos que el home de frappe es suyo
chown -R "${USERNAME}:${USERNAME}" "${USER_HOME}"

echo "   ✅ Home ${USER_HOME} pertenece a ${USERNAME}:${USERNAME}"
echo "   ℹ️  El repo de scripts (/opt/erp-automation-scripts) sigue siendo de root (por seguridad)"

# ----------------------------------------------------------------------
# Resumen final (sin exponer password)
# ----------------------------------------------------------------------

echo ""
echo "━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━"
echo "✅ Usuario '${USERNAME}' configurado"
echo "━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━"
echo "  Home:            ${USER_HOME}"
echo "  Shell:           /bin/bash"
echo "  Sudo:            granular (ver ${SUDOERS_FILE})"
echo "  Miembro de sudo: NO (por seguridad)"
echo "  Credenciales:    ${ENV_FILE}"
echo "  SSH keys:        ${USER_HOME}/.ssh/authorized_keys"
echo "━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━"
echo ""
echo "🕐 Fin: $(date)"
echo ""
echo "ℹ️  Siguiente paso:"
echo "   sudo su - ${USERNAME}"
echo "   # Ya dentro del usuario, correr install-frappe.sh"
