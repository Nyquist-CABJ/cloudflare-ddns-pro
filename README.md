Cloudflare DDNS PRO
Cloudflare DDNS PRO es una utilidad de sistema robusta y profesional diseñada para gestionar registros DNS en Cloudflare. Combina la automatización de un cliente DDNS (para registros tipo A) con la flexibilidad de un gestor de registros estáticos (CNAME, TXT, etc.), permitiéndote controlar toda tu infraestructura DNS desde un único archivo de configuración local.

Características Principales
Sincronización Automática: Mantiene tus registros tipo A actualizados con tu IP pública dinámica.

Gestión de Registros Múltiples: Soporte nativo para registros A, CNAME, TXT, MX, etc.

Seguridad: Ejecución aislada, validación de estado mediante --dry-run y protección contra ejecuciones simultáneas (flock).

Ecosistema Systemd: Integración total con systemd (timer cada 5 minutos, servicios, rotación de logs).

Configuración Inteligente: Soporte multi-zona y multi-dominio con importación automática desde la API de Cloudflare.

Instalación
Asegúrate de estar en la carpeta donde descargaste los archivos.

Dale permisos de ejecución al instalador:

Bash
chmod +x install.sh
Ejecuta el instalador con privilegios de administrador:

Bash
sudo ./install.sh
El instalador instalará las dependencias necesarias (curl, jq), configurará los permisos del sistema y ejecutará un asistente para importar tus zonas actuales.

Configuración
Una vez instalado, el archivo principal reside en /etc/cloudflare-ddns/cloudflare-ddns.conf.

Sintaxis del archivo

# Token global
TOKEN=tu_api_token_aqui

[tudominio.com]
ZONE=tu_zone_id_aqui

# Host        Tipo    Proxy      Contenido
@             A       PROXY      
www           A       PROXY      
vpn           A       NO_PROXY   
app           CNAME   PROXY      example.ddns.net
spf           TXT     NO_PROXY   "v=spf1 include:_spf.google.com ~all"
Registro A vacío: Si dejas la columna de contenido vacía, el script inyectará automáticamente tu IP pública.

Registro A fijo: Si pones una IP, el script la mantendrá estática.

@: Representa la raíz del dominio.

Gestión y Monitoreo
Verificar estado del timer:

Bash
systemctl status cloudflare-ddns.timer
Revisar logs en tiempo real:

Bash
journalctl -u cloudflare-ddns.service -f
Prueba de seguridad (Dry Run):
Si quieres ver qué cambios realizaría el script sin tocar Cloudflare:

Bash
sudo /usr/local/bin/cloudflare-ddns --dry-run
Desinstalación
Para remover completamente la herramienta y limpiar los archivos del sistema:

Bash
sudo ./uninstall.sh
