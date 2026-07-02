# Cloudflare DDNS PRO

Cloudflare DDNS PRO es un cliente **Dynamic DNS (DDNS)** avanzado para **Cloudflare** escrito en **Bash**.

A diferencia de otros clientes DDNS, este proyecto permite administrar **múltiples dominios y zonas DNS** desde un único archivo de configuración, gestionando automáticamente registros **A (DDNS)** y **CNAME (estáticos)** de forma centralizada.

---

# Características

- 🌐 **Soporte Multi-Zona**: administra todos tus dominios desde un solo archivo.
- 🔄 **DDNS Nativo**: actualización automática de IP para registros **A**.
- 📌 **Registros Estáticos**: gestión de registros **A** (IP fija) y **CNAME**.
- 📥 **Importación Inteligente**: el instalador importa automáticamente las zonas existentes desde Cloudflare.
- 🟠 **Control de Proxy**: configuración individual de **PROXY** (nube naranja) o **NO_PROXY** (nube gris) para cada registro.
- 🔒 **Seguro y Robusto**:
  - `set -euo pipefail`
  - Lockfile para evitar ejecuciones simultáneas
  - Modo **Dry Run**
  - Validación de errores
  - Logs sin códigos ANSI
- ⚙️ **Automatización completa**:
  - Instalador interactivo
  - Desinstalador automático
  - Integración con **systemd**
  - Rotación de logs mediante **logrotate**

---

# Requisitos

- Linux
- Bash 4+
- curl
- jq
- systemd (opcional, recomendado)

---

# Instalación

Clonar el repositorio:

```bash
git clone https://github.com/Nyquist-CABJ/cloudflare-ddns-pro.git
cd cloudflare-ddns-pro
```

```bash
chmod +x *.sh
```

Ejecutar el instalador:


```bash
sudo ./install.sh
```

El instalador:

- Detecta automáticamente el gestor de paquetes (`apt`, `dnf`, `yum` o `pacman`).
- Instala las dependencias necesarias (`curl`, `jq`, `bsdmainutils`).
- Configura permisos y directorios.
- Importa automáticamente las zonas y registros existentes desde Cloudflare.
- Configura el servicio y el temporizador de **systemd**.

---

# Configuración

El archivo de configuración se encuentra en:

```text
/etc/cloudflare-ddns/cloudflare-ddns.conf
```

## Formato de registros

La sintaxis es:

```text
HOST | TIPO | PROXY | CONTENIDO
```

Ejemplo:

```ini
TOKEN=tu_api_token_aqui

[example.ar]
ZONE=TU_DOMAIN_ID_AQUI

# Host      Tipo    Proxy      Contenido
@            A       PROXY
www          A       PROXY
vpn          A       NO_PROXY
app          CNAME   PROXY      example.ddns.net
```

### Registros tipo A

Si la columna **Contenido** queda vacía, el script utilizará automáticamente la IP pública actual (DDNS).

```text
www    A    PROXY
```

También es posible especificar una IP fija.

```text
server A    PROXY    192.168.1.100
```

### Registros tipo CNAME

Para los registros **CNAME** es obligatorio indicar el dominio de destino.

```text
app    CNAME    PROXY    nyquist.ddns.net
```

---

# Ejecución

## Dry Run

Simula todas las operaciones sin modificar ningún registro en Cloudflare.

```bash
sudo /usr/local/bin/cloudflare-ddns --dry-run
```

---

## Ejecución manual

```bash
sudo /usr/local/bin/cloudflare-ddns
```

---

# Monitorización

El servicio utiliza **systemd**.

Consultar el estado del temporizador:

```bash
systemctl status cloudflare-ddns.timer
```

Consultar los logs en tiempo real:

```bash
journalctl -u cloudflare-ddns.service -f
```

Consultar el log generado por la aplicación:

```text
/var/log/cloudflare-ddns.log
```

---

# Estructura del proyecto

```text
cloudflare-ddns-pro/
├── cloudflare-ddns.sh          # Motor principal
├── install.sh                  # Instalador interactivo
├── uninstall.sh                # Desinstalador automático
├── cloudflare-ddns.service     # Servicio Systemd
├── cloudflare-ddns.timer       # Temporizador Systemd
├── cloudflare-ddns.logrotate   # Rotación de logs
├── LICENSE
└── README.md
```

---

# Desinstalación

Para eliminar completamente la herramienta:

```bash
sudo ./uninstall.sh
```

El desinstalador elimina:

- Ejecutable
- Servicio systemd
- Timer
- Configuración (opcional)
- Logs (opcional)
- Caché
- Logrotate

---

# Licencia

Este proyecto se distribuye bajo la licencia **MIT**.

Consulta el archivo **LICENSE** para más información.

---

# Autor

**Daniel Finke**

GitHub: https://github.com/Nyquist-CABJ

---

## ⭐ ¿Te resultó útil?

Si este proyecto te ha sido útil, considera darle una **⭐** al repositorio para apoyar el desarrollo.
