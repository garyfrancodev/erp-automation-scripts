# erp-automation-scripts

Scripts modulares y CLI de administración para preparar y operar servidores Ubuntu (22.04 LTS / 24.04 LTS) con **Frappe Bench v15 + ERPNext**.

---

## ⚡ Instalación en 1 Solo Paso (Servidor Nuevo)

En un VPS recién creado con Ubuntu 22.04 LTS, conéctate por SSH como `root` y pega este comando:

```bash
curl -sSL https://raw.githubusercontent.com/garyfrancodev/erp-automation-scripts/main/bootstrap.sh | bash
```
> **Tip de Conectividad:** Para evitar que la instalación se corte si se desconecta tu internet durante descargas pesadas (`bench init`), se recomienda iniciar una sesión persistente antes con: `tmux` o `screen`.

El script se encarga de instalar Git/Curl, clonar el repositorio en `/opt/erp-automation-scripts`, autodetectar la IP pública real de tu VPS y ejecutar la configuración inicial completa.

---

## 🛠️ CLI de Operación Rápida (`./erp`)

El repositorio incluye un CLI unificado en la raíz para operar el servidor sin memorizar rutas:

```bash
# Ver estado de los servicios (Nginx, MariaDB, Fail2ban, Supervisor)
./erp status

# Crear un nuevo sitio de cliente (crea DNS en Linode e instala apps)
./erp site create cliente1

# Activar SSL Let's Encrypt para un sitio
./erp site ssl cliente1.mandox.com.bo admin@empresa.com

# Respaldos
./erp backup create cliente1
./erp backup copy cliente1 cliente2
./erp backup restore cliente2

# Configuración de bench (como usuario frappe)
./erp bench init
./erp bench apps
./erp bench prod
```

---

## 📁 Estructura del repositorio

```text
erp-automation-scripts/
├── erp                                         # CLI unificado de administración
├── setup.sh                                    # Orquestador del servidor base (root / sudo)
├── scripts/
│   ├── core/                                   # Biblioteca y variables globales
│   │   ├── config.env
│   │   └── lib.sh
│   │
│   ├── 01-server-setup/                        # [Fase 1: ROOT / SUDO]
│   │   ├── 01-update-system.sh                 # Actualiza paquetes del sistema
│   │   ├── 02-create-frappe-user.sh            # Crea usuario 'frappe' con sudo
│   │   ├── 03-prepare-server.sh                # Swap, UFW, límites nofile y Logrotate
│   │   ├── 04-install-dependencies.sh          # Node 20, Yarn, wkhtmltopdf, Fail2ban...
│   │   └── 05-install-mariadb.sh               # MariaDB seguro + tuning de producción
│   │
│   ├── 02-bench-setup/                         # [Fase 2: Usuario FRAPPE]
│   │   ├── 01-install-frappe.sh                # Instala bench vía pipx e inicializa
│   │   ├── 02-install-apps.sh                  # Descarga ERPNext, HRMS y Webshop
│   │   └── 03-setup-production.sh              # Nginx, Supervisor y crontab de backups
│   │
│   ├── sites/                                  # [Operación diaria / por cliente]
│   │   ├── create-site.sh                      # Automatiza Linode DNS + new-site
│   │   └── enable-ssl.sh                       # Certbot SSL + verificación de DNS
│   │
│   └── backups/                                # [Mantenimiento y respaldos]
│       ├── generate-backup.sh
│       ├── copy-backup.sh
│       └── restore-backup.sh
```

---

## 🚀 Instalación en un servidor nuevo (Paso a Paso)

### Paso 1: Configurar el servidor base (como `root` o usuario con `sudo`)
Ejecuta el asistente principal:
```bash
bash setup.sh
# o: ./erp server setup
```

> **Nota:** Si al terminar el sistema indica que requiere reinicio (`/var/run/reboot-required`), reinicia el VPS con `sudo reboot` antes de pasar a la siguiente fase.

---

### Paso 2: Inicializar Bench y Producción (como usuario `frappe`)
Cambia al usuario `frappe`:
```bash
su - frappe
cd /opt/erp-automation-scripts   # o la ruta donde clonaste el repositorio
```
Ejecuta los pasos de inicialización:
```bash
./erp bench init
./erp bench apps
./erp bench prod
```

---

### Paso 3: Crear sitios por cliente y activar SSL (como usuario `frappe`)
Crea un nuevo sitio con registro DNS automático en Linode y las aplicaciones preconfiguradas:
```bash
./erp site create cliente1
```
Cuando el DNS del subdominio haya propagado hacia la IP del servidor:
```bash
./erp site ssl cliente1.mandox.com.bo tu-correo@ejemplo.com
```

---

## 🛡️ Seguridad y Mantenimiento Integrados

- **Fail2ban:** Incluye filtro para monitorear intentos de login fallidos en Frappe (`POST /api/method/login`) y bloquear IPs atacantes en puertos 80 y 443 por 24 horas.
- **Logrotate:** Configurado en `/etc/logrotate.d/frappe-bench` con `copytruncate` semanal para evitar que los logs de Supervisor/Gunicorn consuman el almacenamiento del disco.
- **Tuning de MariaDB:** Configurado con `max_allowed_packet = 256M`, `wait_timeout = 28800` y sección `[mysqldump]` para tolerar respaldos y migraciones pesadas sin cortes.
- **Respaldos Automáticos:** `bench setup backups` programa automáticamente la copia de seguridad diaria con rotación en el crontab del usuario `frappe`.
- **Límites de Sistema:** Se elevan los límites de archivos abiertos (`nofile: 65535`) y descriptores del kernel (`fs.file-max: 2097152`).

---

## ⚙️ Configuración y Secretos

1. **[`scripts/core/config.env`](scripts/core/config.env):** Parámetros globales por defecto (rama de Frappe, dominio, IP del servidor, zona horaria, tamaño de swap, apps a instalar). Se pueden sobreescribir en cualquier comando:
   ```bash
   DOMAIN_NAME=otrodominio.com ./erp site create cliente2
   ```
2. **`.env` (en la raíz, permisos 600, ignorado en Git):** Almacén seguro donde los scripts guardan las contraseñas autogeneradas (`FRAPPE_PASSWORD`, `DB_ROOT_USER`, `DB_ROOT_PASSWORD`, `ADMIN_PASSWORD_<SITIO>`).
   Para consultarlas:
   ```bash
   sudo cat .env
   ```
3. **Credenciales Linode:** Se obtienen automáticamente mediante 1Password CLI (`op read`) o exportando la variable de entorno `ERP_DOMAINS_API`.