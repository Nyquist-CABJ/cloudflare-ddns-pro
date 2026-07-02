#!/bin/bash
if [[ $EUID -ne 0 ]]; then echo "Este script debe ejecutarse como root (usa sudo)"; exit 1; fi

echo "Deteniendo servicios..."
systemctl stop cloudflare-ddns.timer 2>/dev/null
systemctl disable cloudflare-ddns.timer 2>/dev/null

echo "Eliminando archivos del sistema..."
rm -f /usr/local/bin/cloudflare-ddns
rm -f /etc/systemd/system/cloudflare-ddns.service
rm -f /etc/systemd/system/cloudflare-ddns.timer
rm -f /etc/logrotate.d/cloudflare-ddns
rm -rf /var/lib/cloudflare-ddns

systemctl daemon-reload

read -p "¿Desea eliminar la configuración en /etc/cloudflare-ddns/? [y/N]: " choice
case "$choice" in 
  y|Y ) rm -rf /etc/cloudflare-ddns/ ; echo "Configuración eliminada." ;;
  * ) echo "Configuración conservada." ;;
esac

echo "✔ Desinstalación completa."
