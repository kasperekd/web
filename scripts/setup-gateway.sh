#!/bin/bash
ROLE="gateway"
source /opt/web/scripts/common.sh

log "--- Настройка Gateway (NAT, DNS, DHCP) ---"
setup_base_utils
set_hostname_and_hosts "gateway" "$GW_IP"

log "Настройка Netplan (WAN+LAN)..."
rm -f /etc/netplan/*.yaml
cat <<EOF > /etc/netplan/01-gateway.yaml
network:
  version: 2
  renderer: networkd
  ethernets:
    $WAN_IFACE:
      dhcp4: true
    $LAN_IFACE:
      dhcp4: false
      addresses:
        - ${GW_IP}/${LAN_CIDR}
      nameservers:
        addresses: [127.0.0.1, ${UPSTREAM_DNS}]
        search: [${DOMAIN}]
EOF
chmod 600 /etc/netplan/01-gateway.yaml
netplan apply

log "Включение IP Forwarding и NAT..."
backup_file "/etc/sysctl.conf"
sed -i '/net.ipv4.ip_forward/d' /etc/sysctl.conf
echo "net.ipv4.ip_forward=1" >> /etc/sysctl.conf
sysctl -p

apt-get install -y -qq iptables-persistent
iptables -F
iptables -X
iptables -t nat -F
iptables -t nat -X
iptables -t nat -A POSTROUTING -o $WAN_IFACE -j MASQUERADE
iptables -A FORWARD -i $WAN_IFACE -o $WAN_IFACE -j REJECT
iptables -I FORWARD -p tcp --tcp-flags SYN,RST SYN -j TCPMSS --clamp-mss-to-pmtu
# Перенаправление DNS-запросов (из ЛР 4)
# iptables -t nat -A PREROUTING -i $LAN_IFACE -p tcp --dport 53 -j DNAT --to-destination ${UPSTREAM_DNS}:53
# iptables -t nat -A PREROUTING -i $LAN_IFACE -p udp --dport 53 -j DNAT --to-destination ${UPSTREAM_DNS}:53
iptables-save > /etc/iptables/rules.v4

log "Установка Bind9 и ISC-DHCP-Server..."
apt-get install -y -qq bind9 bind9utils bind9-doc isc-dhcp-server

log "Настройка Bind9..."
backup_file "/etc/bind/named.conf.options"
cat <<EOF > /etc/bind/named.conf.options
options {
    directory "/var/cache/bind";
    forwarders { ${UPSTREAM_DNS}; };
    dnssec-validation auto;
    listen-on { 127.0.0.1; ${GW_IP}; };
    allow-query { any; };
};
EOF

backup_file "/etc/bind/named.conf.local"
cat <<EOF > /etc/bind/named.conf.local
include "/etc/bind/rndc.key";
controls { inet 127.0.0.1 allow { localhost; } keys { rndc-key; }; };

zone "${DOMAIN}" IN {
    type master;
    file "/var/lib/bind/forward.db";
    allow-update { key rndc-key; };
};

zone "${VARIANT}.168.192.in-addr.arpa" IN {
    type master;
    file "/var/lib/bind/reverse.db";
    allow-update { key rndc-key; };
};
EOF

# Инициализация файлов зон
if [ ! -f /var/lib/bind/forward.db ]; then
cat <<EOF > /var/lib/bind/forward.db
\$TTL 86400
${DOMAIN}. IN SOA gateway.${DOMAIN}. admin.${DOMAIN}. (
 2023101001 604800 86400 2419200 604800 )
 IN NS gateway.${DOMAIN}.
 IN A ${GW_IP}
localhost IN A 127.0.0.1
gateway IN A ${GW_IP}
seafile IN A ${SEAFILE_IP}
mail IN A ${MAIL_IP}
wordpress IN A ${WP_IP}
privatebin IN A ${PBIN_IP}
EOF
fi

if [ ! -f /var/lib/bind/reverse.db ]; then
cat <<EOF > /var/lib/bind/reverse.db
\$TTL 86400
${VARIANT}.168.192.in-addr.arpa. IN SOA gateway.${DOMAIN}. admin.${DOMAIN}. (
 2023101001 10800 3600 604800 3600 )
 IN NS gateway.${DOMAIN}.
1 IN PTR gateway.${DOMAIN}.
4 IN PTR seafile.${DOMAIN}.
5 IN PTR mail.${DOMAIN}.
6 IN PTR wordpress.${DOMAIN}.
7 IN PTR privatebin.${DOMAIN}.
EOF
fi

chown -R bind:bind /var/lib/bind/
chmod -R 775 /var/lib/bind/
systemctl restart bind9

log "Настройка DHCP сервера..."
sed -i "s/^INTERFACESv4=.*/INTERFACESv4=\"$LAN_IFACE\"/" /etc/default/isc-dhcp-server

mkdir -p /etc/dhcp/ddns-keys
cp -p /etc/bind/rndc.key /etc/dhcp/ddns-keys/rndc.key
chown dhcpd:dhcpd /etc/dhcp/ddns-keys/rndc.key 2>/dev/null || true

cat <<EOF > /etc/dhcp/dhcpd.conf
authoritative;
include "/etc/dhcp/ddns-keys/rndc.key";
ddns-updates on;
ddns-update-style standard;
ddns-domainname "${DOMAIN}";

zone ${DOMAIN}. { primary ${GW_IP}; key rndc-key; }
zone ${VARIANT}.168.192.in-addr.arpa. { primary ${GW_IP}; key rndc-key; }

subnet ${LAN_SUBNET} netmask ${LAN_NETMASK} {
    range ${DHCP_START} ${DHCP_END};
    option domain-name-servers ${GW_IP};
    option domain-name "${DOMAIN}";
    option routers ${GW_IP};
    option broadcast-address 192.168.${VARIANT}.255;
    default-lease-time 604800;
    max-lease-time 604800;
}
EOF

# Фикс прав apparmor для dhcp (чтобы мог читать ключ)
sed -i '/\/etc\/bind\/rndc.key r,/d' /etc/apparmor.d/usr.sbin.dhcpd 2>/dev/null
echo "  /etc/dhcp/ddns-keys/rndc.key r," >> /etc/apparmor.d/usr.sbin.dhcpd 2>/dev/null || true
systemctl reload apparmor 2>/dev/null || true

systemctl restart isc-dhcp-server
log "--- Шлюз полностью настроен ---"