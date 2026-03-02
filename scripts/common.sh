#!/bin/bash
# scripts/common.sh

CONFIG_FILE="/opt/lab-setup/configs/lab-config.conf"
if[ -f "$CONFIG_FILE" ]; then
    source "$CONFIG_FILE"
else
    echo "ОШИБКА: Файл конфигурации не найден ($CONFIG_FILE)"
    exit 1
fi

LOG_FILE="/var/log/setup-${ROLE}.log"

log() {
    echo "$(date '+%Y-%m-%d %H:%M:%S') [INFO] $1" | tee -a "$LOG_FILE"
}

err() {
    echo "$(date '+%Y-%m-%d %H:%M:%S') [ERROR] $1" | tee -a "$LOG_FILE" >&2
    exit 1
}

backup_file() {
    if [ -f "$1" ] && [ ! -f "$1.orig" ]; then
        cp -p "$1" "$1.orig"
    fi
}

setup_base_utils() {
    export DEBIAN_FRONTEND=noninteractive
    apt-get update -qq
    apt-get install -y -qq curl vim jq net-tools iproute2 dnsutils
}

apply_netplan_static() {
    local host_ip=$1
    log "Настройка статического IP: $host_ip"
    rm -f /etc/netplan/*.yaml
    cat <<EOF > /etc/netplan/01-static.yaml
network:
  version: 2
  renderer: networkd
  ethernets:
    $SINGLE_IFACE:
      dhcp4: false
      addresses:
        - ${host_ip}/${LAN_CIDR}
      routes:
        - to: default
          via: ${GW_IP}
      nameservers:
        addresses: [${GW_IP}]
        search: [${DOMAIN}]
EOF
    chmod 600 /etc/netplan/01-static.yaml
    netplan apply
    sleep 3
}

set_hostname_and_hosts() {
    local hname=$1
    local hip=$2
    hostnamectl set-hostname "$hname"
    sed -i "/$hname/d" /etc/hosts
    echo "$hip $hname ${hname}.${DOMAIN}" >> /etc/hosts
    # Фикс для systemd-resolved (чтобы .local работал без mDNS)
    sed -i 's/#ResolveUnicastSingleLabel=no/ResolveUnicastSingleLabel=yes/' /etc/systemd/resolved.conf
    systemctl restart systemd-resolved
}