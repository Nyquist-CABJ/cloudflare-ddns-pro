#!/bin/bash
set -euo pipefail

START_TIME=$(date +%s)
VERSION="15.0"

CONF="${CF_DDNS_CONF:-/etc/cloudflare-ddns/cloudflare-ddns.conf}"
LOG_FILE="/var/log/cloudflare-ddns.log"
IP_CACHE="/var/lib/cloudflare-ddns/ip.cache"
LOCK_FILE="/var/lib/cloudflare-ddns/cloudflare-ddns.lock"

log() { printf '%s\n' "$*"; }

touch "$LOG_FILE" 2>/dev/null || { log "[FATAL] No se puede escribir en $LOG_FILE. Verifica permisos."; exit 1; }

exec 9> "$LOCK_FILE"
if ! flock -n 9; then log "$(date '+%Y-%m-%d %H:%M:%S') [FATAL] El script ya está en ejecución."; exit 1; fi

DRY_RUN=0; [[ "${1:-}" == "--dry-run" ]] && DRY_RUN=1
USE_COLORS=0; [[ -t 1 ]] && USE_COLORS=1

exec > >(tee >(sed -r 's/\x1B\[[0-9;]*[mK]//g' >> "$LOG_FILE")) 2>&1

log ""
log "=========================================="
if [[ $DRY_RUN -eq 1 ]]; then log " Cloudflare DDNS PRO v$VERSION [DRY-RUN]"; else log " Cloudflare DDNS PRO v$VERSION"; fi
log "=========================================="
log "Fecha: $(date)"
log ""

CNT_ZONES=0; CNT_OK=0; CNT_UPDATED=0; CNT_CREATED=0; CNT_ERRORS=0

print_status() {
    local tag=$1 type=$2 domain=$3 color="" reset="\e[0m"
    if [[ "$USE_COLORS" == "1" ]]; then
        case "$tag" in
            "[ OK ]") color="\e[32m" ;;
            "[UPD ]") color="\e[33m" ;;
            "[NEW ]") color="\e[36m" ;;
            "[ERR ]") color="\e[31m" ;;
        esac
    else reset=""; fi
    printf "${color}%-8s${reset} %-8s %s\n" "$tag" "$type" "$domain"
}

notify_error() {
    local domain=$1 msg=$2
    ((CNT_ERRORS+=1))
    log "[ERROR] $domain - $msg"
    print_status "[ERR ]" "-" "$domain"
    if [[ -n "${TG_BOT_TOKEN:-}" && -n "${TG_CHAT_ID:-}" && $DRY_RUN -eq 0 ]]; then
        curl -s -X POST "https://api.telegram.org/bot$TG_BOT_TOKEN/sendMessage" -d chat_id="$TG_CHAT_ID" -d text="🚨 CF DDNS Error en $domain: $msg" >/dev/null || true
    fi
}

for cmd in curl jq awk sed tr; do
    if ! command -v "$cmd" >/dev/null 2>&1; then log "[FATAL] falta $cmd"; exit 1; fi
done

if [[ ! -f "$CONF" ]]; then log "[FATAL] No existe el archivo de configuración: $CONF"; exit 1; fi

declare -A ZONE_IDS MANAGED_HOSTS
TOKEN="" TG_BOT_TOKEN="" TG_CHAT_ID="" current_zone=""

# PARSER: host | tipo | proxy | contenido
while IFS= read -r line || [[ -n "$line" ]]; do
    line=$(echo "$line" | sed 's/#.*//; s/^[[:space:]]*//; s/[[:space:]]*$//')
    if [[ -z "$line" ]]; then continue; fi

    if [[ "$line" == TOKEN=* ]]; then TOKEN="${line#TOKEN=}"; continue; fi
    if [[ "$line" == TG_BOT_TOKEN=* ]]; then TG_BOT_TOKEN="${line#TG_BOT_TOKEN=}"; continue; fi
    if [[ "$line" == TG_CHAT_ID=* ]]; then TG_CHAT_ID="${line#TG_CHAT_ID=}"; continue; fi

    if [[ "$line" =~ ^\[(.*)\]$ ]]; then current_zone="${BASH_REMATCH[1]}"; continue; fi

    if [[ -n "$current_zone" ]]; then
        if [[ "$line" == ZONE=* ]]; then ZONE_IDS["$current_zone"]="${line#ZONE=}"
        else
            set -f
            set -- $line
            set +f
            
            host=$1
            type=${2:-A}
            proxy_mode=${3:-PROXY}
            shift 3 2>/dev/null || true
            content="$*"

            # Solo gestionamos A y CNAME
            if [[ "$type" != "A" && "$type" != "CNAME" ]]; then continue; fi

            if [[ "$host" == "@" ]]; then full_host="$current_zone"; else full_host="${host}.${current_zone}"; fi
            MANAGED_HOSTS["${current_zone}|${full_host}|${type}"]="${proxy_mode}|||${content}"
        fi
    fi
done < "$CONF"

if [[ -z "$TOKEN" ]]; then log "[FATAL] Falta TOKEN en la configuración."; exit 1; fi

PUBLIC_IP=$(curl -4 -s https://ipv4.icanhazip.com | tr -d '\n' || true)
if [[ -z "$PUBLIC_IP" ]]; then log "[FATAL] no se pudo obtener IP pública"; exit 1; fi

SKIP_IP_UPDATE=0
if [[ -f "$IP_CACHE" ]]; then
    if [[ "$(<"$IP_CACHE")" == "$PUBLIC_IP" ]]; then SKIP_IP_UPDATE=1; fi
fi

log "IP actual: $PUBLIC_IP"
if [[ $SKIP_IP_UPDATE -eq 1 ]]; then log "La IP no ha cambiado desde la última ejecución."; fi
log ""

cf_api() {
    local method=$1 endpoint=$2 payload=$3
    if [[ -n "$payload" ]]; then
        curl -s -X "$method" -H "Authorization: Bearer $TOKEN" -H "Content-Type: application/json" "https://api.cloudflare.com/client/v4/$endpoint" --data "$payload" || true
    else
        curl -s -X "$method" -H "Authorization: Bearer $TOKEN" "https://api.cloudflare.com/client/v4/$endpoint" || true
    fi
}

cf_update() {
    local zone=$1 id=$2 name=$3 type=$4 proxied=$5 content=$6
    if [[ $DRY_RUN -eq 1 ]]; then return 0; fi
    [[ "$type" == "A" && -z "$content" ]] && content="$PUBLIC_IP"
    
    local p_bool="true"; [[ "$proxied" == "NO_PROXY" || "$proxied" == "false" ]] && p_bool="false"
    local payload=$(jq -n --arg t "$type" --arg n "$name" --arg c "$content" --argjson p "$p_bool" '{type: $t, name: $n, content: $c, ttl: 1, proxied: $p}')
    
    local response=$(cf_api "PUT" "zones/$zone/dns_records/$id" "$payload")
    if [[ "$(echo "$response" | jq -r '.success' || echo 'false')" != "true" ]]; then log "[API RESPONSE] $name:"; echo "$response" | jq -c '.errors' || true; return 1; fi
    return 0
}

cf_create() {
    local zone=$1 name=$2 type=$3 proxied=$4 content=$5
    if [[ $DRY_RUN -eq 1 ]]; then return 0; fi
    [[ "$type" == "A" && -z "$content" ]] && content="$PUBLIC_IP"
    
    local p_bool="true"; [[ "$proxied" == "NO_PROXY" || "$proxied" == "false" ]] && p_bool="false"
    local payload=$(jq -n --arg t "$type" --arg n "$name" --arg c "$content" --argjson p "$p_bool" '{type: $t, name: $n, content: $c, ttl: 1, proxied: $p}')
    
    local response=$(cf_api "POST" "zones/$zone/dns_records" "$payload")
    if [[ "$(echo "$response" | jq -r '.success' || echo 'false')" != "true" ]]; then log "[API RESPONSE] $name:"; echo "$response" | jq -c '.errors' || true; return 1; fi
    return 0
}

for DOMAIN in "${!ZONE_IDS[@]}"; do
    ZONE="${ZONE_IDS[$DOMAIN]}"
    ((CNT_ZONES+=1))
    
    log "------------------------------------------"
    log "Zona: $DOMAIN"
    log "------------------------------------------"

    DNS=$(cf_api "GET" "zones/$ZONE/dns_records?per_page=5000" "")
    if [[ "$(echo "$DNS" | jq -r '.success' || echo 'false')" != "true" ]]; then
        notify_error "$DOMAIN" "API Error al obtener registros"
        echo "$DNS" | jq -c '.errors' || true
        continue
    fi

    mapfile -t RECORDS < <(echo "$DNS" | jq -c '.result[]' || true)

    unset EXISTING
    declare -A EXISTING
    for r in "${RECORDS[@]}"; do EXISTING["$(jq -r '.name' <<< "$r")|$(jq -r '.type' <<< "$r")"]=1; done

    # 1. PROCESAR EXISTENTES (Solo A y CNAME declarados en el conf)
    for r in "${RECORDS[@]}"; do
        ID=$(jq -r '.id' <<< "$r"); NAME=$(jq -r '.name' <<< "$r"); TYPE=$(jq -r '.type' <<< "$r"); 
        CONTENT=$(jq -r '.content' <<< "$r"); PROXIED_CURRENT=$(jq -r '.proxied' <<< "$r")

        if [[ "$TYPE" != "A" && "$TYPE" != "CNAME" ]]; then continue; fi
        if [[ -z "${MANAGED_HOSTS["${DOMAIN}|${NAME}|${TYPE}"]:-}" ]]; then continue; fi

        CONF_VAL="${MANAGED_HOSTS["${DOMAIN}|${NAME}|${TYPE}"]}"
        DESIRED_PROXY="${CONF_VAL%%|||*}"
        DESIRED_CONTENT="${CONF_VAL##*|||}"
        
        PROXIED="true"; [[ "$DESIRED_PROXY" == "NO_PROXY" ]] && PROXIED="false"
        EXPECTED_CONTENT="$DESIRED_CONTENT"
        [[ "$TYPE" == "A" && -z "$EXPECTED_CONTENT" ]] && EXPECTED_CONTENT="$PUBLIC_IP"

        if [[ "$CONTENT" == "$EXPECTED_CONTENT" && "$PROXIED_CURRENT" == "$PROXIED" ]]; then
            print_status "[ OK ]" "$TYPE" "$NAME"
            ((CNT_OK+=1))
            continue
        fi

        print_status "[UPD ]" "$TYPE" "$NAME"
        if cf_update "$ZONE" "$ID" "$NAME" "$TYPE" "$DESIRED_PROXY" "$DESIRED_CONTENT"; then ((CNT_UPDATED+=1)); else notify_error "$NAME" "Fallo al actualizar"; fi
    done

    # 2. AUTO CREATE (Lo que está en el .conf pero no en Cloudflare)
    for key in "${!MANAGED_HOSTS[@]}"; do
        if [[ "$key" != "${DOMAIN}|"* ]]; then continue; fi
        
        tmp="${key#*|}"
        full_host="${tmp%|*}"
        record_type="${tmp##*|}"
        
        if [[ -z "${EXISTING["$full_host|$record_type"]:-}" ]]; then
            CONF_VAL="${MANAGED_HOSTS[$key]}"
            DESIRED_PROXY="${CONF_VAL%%|||*}"
            DESIRED_CONTENT="${CONF_VAL##*|||}"

            print_status "[NEW ]" "$record_type" "$full_host"
            if cf_create "$ZONE" "$full_host" "$record_type" "$DESIRED_PROXY" "$DESIRED_CONTENT"; then ((CNT_CREATED+=1)); else notify_error "$full_host" "Fallo al crear"; fi
        fi
    done
done

if [[ $DRY_RUN -eq 0 && $CNT_ERRORS -eq 0 && $SKIP_IP_UPDATE -eq 0 ]]; then
    echo "$PUBLIC_IP" > "$IP_CACHE" || log "[ERROR] No se guardó caché de IP"
fi

END_TIME=$(date +%s); DURATION=$((END_TIME - START_TIME))
if [[ $CNT_ERRORS -eq 0 ]]; then RESULT="SUCCESS"; else RESULT="COMPLETED WITH ERRORS"; fi

log ""
log "=========================================="
log " Cloudflare DDNS PRO v$VERSION"
log "=========================================="
log ""
printf "%-17s: %d\n" "Zonas procesadas" "$CNT_ZONES"
printf "%-17s: %d\n" "Registros OK" "$CNT_OK"
printf "%-17s: %d\n" "Actualizados" "$CNT_UPDATED"
printf "%-17s: %d\n" "Creados" "$CNT_CREATED"
printf "%-17s: %d\n" "Errores" "$CNT_ERRORS"
log ""
printf "%-17s: %s s\n" "Tiempo" "$DURATION"
printf "%-17s: %s\n" "IP pública" "$PUBLIC_IP"
log ""
printf "%-17s: %s\n" "Resultado" "$RESULT"
log "=========================================="
