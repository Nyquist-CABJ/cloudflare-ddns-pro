#!/bin/bash
if [[ $EUID -ne 0 ]]; then 
    echo "Este script debe ejecutarse como root (usa sudo ./install.sh)"
    exit 1
fi

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
BIN="/usr/local/bin/cloudflare-ddns"
CONF_DIR="/etc/cloudflare-ddns"
CONF_FILE="$CONF_DIR/cloudflare-ddns.conf"
REAL_USER=${SUDO_USER:-$(whoami)}

echo "=========================================="
echo " Cloudflare DDNS PRO Installer v15.0"
echo "=========================================="

echo "1. Realizando validaciones pre-instalación..."
for file in cloudflare-ddns.sh cloudflare-ddns.service cloudflare-ddns.timer cloudflare-ddns.logrotate; do
    if [[ ! -f "$SCRIPT_DIR/$file" ]]; then
        echo "[FATAL] Falta el archivo $file en el directorio de instalación."
        exit 1
    fi
done

echo "2. Verificando dependencias..."
if command -v apt >/dev/null 2>&1; then
    apt update -qq && apt install -y curl jq bsdmainutils
elif command -v dnf >/dev/null 2>&1; then
    dnf install -y curl jq util-linux
elif command -v yum >/dev/null 2>&1; then
    yum install -y curl jq util-linux
elif command -v pacman >/dev/null 2>&1; then
    pacman -Sy --noconfirm curl jq util-linux
else
    echo "[FATAL] Gestor de paquetes no detectado."
    exit 1
fi

echo "3. Preparando directorios del sistema..."
mkdir -p "$CONF_DIR" /var/lib/cloudflare-ddns /var/log/
touch /var/log/cloudflare-ddns.log

cp "$SCRIPT_DIR/cloudflare-ddns.sh" "$BIN"
chmod 755 "$BIN"

echo "4. Asistente de configuración..."
if [[ -f "$CONF_FILE" ]]; then
    read -p "   Ya existe configuración en $CONF_FILE. ¿Deseas sobrescribirla? [y/N]: " overwrite
fi

if [[ ! -f "$CONF_FILE" || "$overwrite" =~ ^[Yy]$ ]]; then
    read -p "   ➜ API Token de Cloudflare: " CF_TOKEN

    cat > "$CONF_FILE" <<EOF
TOKEN=$CF_TOKEN

###########################################################
# Sintaxis de registros:
# Host    Tipo    Proxy         Contenido
#
# Ejemplos:
# @       A       PROXY         (Vacío = usa tu IP pública automáticamente)
# server  A       PROXY         200.10.20.30 (IP estática manual)
# www     CNAME   PROXY         midominio.com
###########################################################

EOF

    while true; do
        read -p "   ¿Desea configurar una zona DNS? [Y/n]: " add_zone
        if [[ "$add_zone" =~ ^[Nn]$ ]]; then break; fi

        read -p "      ➜ Dominio (ej. dftechno.ar): " CF_DOMAIN
        read -p "      ➜ Zone ID de $CF_DOMAIN: " CF_ZONE_ID

        cat >> "$CONF_FILE" <<EOF
[$CF_DOMAIN]
ZONE=$CF_ZONE_ID

EOF

        read -p "      ➜ ¿Desea importar los registros A y CNAME de Cloudflare? [Y/n]: " import_records
        if [[ ! "$import_records" =~ ^[Nn]$ ]]; then
            echo "        Importando registros de $CF_DOMAIN..."
            RECORDS=$(curl -s -X GET "https://api.cloudflare.com/client/v4/zones/$CF_ZONE_ID/dns_records?per_page=5000" \
                -H "Authorization: Bearer $CF_TOKEN" -H "Content-Type: application/json")
            
            # Filtro JQ: Solo A y CNAME. Si es A, omite el contenido (IP).
            echo "$RECORDS" | jq -r --arg dom "$CF_DOMAIN" '
                .result[] | select(.type == "A" or .type == "CNAME") | 
                .name as $n | 
                (if $n == $dom then "@" else ($n | sub("."+$dom+"$"; "")) end) as $host | 
                (if .proxied then "PROXY" else "NO_PROXY" end) as $px | 
                (if .type == "A" then "" else .content end) as $val |
                "\($host) \(.type) \($px) \($val)"
            ' | column -t >> "$CONF_FILE"
            echo "" >> "$CONF_FILE"
        else
            cat >> "$CONF_FILE" <<EOF
@       A       PROXY
www     CNAME   PROXY   $CF_DOMAIN

EOF
        fi
    done
    echo "✔ Configuración base generada en $CONF_FILE"
else
    echo "✔ Configuración existente preservada."
fi

chown -R "$REAL_USER":"$REAL_USER" "$CONF_DIR"
chown -R "$REAL_USER":"$REAL_USER" /var/lib/cloudflare-ddns
chown "$REAL_USER":"$REAL_USER" /var/log/cloudflare-ddns.log

echo "5. Instalando servicios y logrotate..."
cp "$SCRIPT_DIR/cloudflare-ddns.service" /etc/systemd/system/
cp "$SCRIPT_DIR/cloudflare-ddns.timer" /etc/systemd/system/
cp "$SCRIPT_DIR/cloudflare-ddns.logrotate" /etc/logrotate.d/cloudflare-ddns

sed -i "s|USER_PLACEHOLDER|$REAL_USER|g" /etc/systemd/system/cloudflare-ddns.service
sed -i "s|USER_PLACEHOLDER|$REAL_USER|g" /etc/logrotate.d/cloudflare-ddns
systemctl daemon-reload

echo ""
read -p "¿Desea habilitar la ejecución automática cada 5 minutos? [Y/n]: " enable_timer
if [[ ! "$enable_timer" =~ ^[Nn]$ ]]; then
    systemctl enable --now cloudflare-ddns.timer
    TIMER_MSG="✔ Timer instalado y activado (cada 5 min)"
else
    TIMER_MSG="ℹ Timer NO iniciado (Habilitar con: sudo systemctl enable --now cloudflare-ddns.timer)"
fi

echo ""
echo "Ejecutando prueba automatizada (--dry-run)..."
echo "------------------------------------------"

if sudo -u "$REAL_USER" "$BIN" --dry-run; then
    echo "------------------------------------------"
    echo "✔ Instalación correcta"
    echo "✔ Configuración válida"
    echo "✔ Acceso a Cloudflare OK"
    echo "$TIMER_MSG"
else
    echo "------------------------------------------"
    echo "❌ La prueba ha fallado. Revisa el Token de API o la conexión a internet."
fi
