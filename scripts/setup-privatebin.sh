#!/bin/bash
ROLE="privatebin"
source /opt/lab-setup/scripts/common.sh

log "--- Настройка PrivateBin ---"
setup_base_utils
set_hostname_and_hosts "privatebin" "$PBIN_IP"
apply_netplan_static "$PBIN_IP"

log "Установка Apache2, PHP и Git..."
apt-get install -y -qq apache2 php php-xml php-mbstring php-mysql php-json php-pdo git openssl

log "Генерация самоподписанного SSL сертификата..."
mkdir -p /etc/ssl/private /etc/ssl/certs
openssl req -x509 -nodes -days 365 -newkey rsa:2048 \
  -keyout /etc/ssl/private/apache-selfsigned.key \
  -out /etc/ssl/certs/apache-selfsigned.crt \
  -subj "/C=RU/ST=Novosibirsk/L=Novosibirsk/O=Sibsutis/OU=${GROUP_NAME}/CN=privatebin.${DOMAIN}"

log "Настройка Apache2 (VirtualHosts 80 -> 443)..."
cat <<EOF > /etc/apache2/sites-available/privatebin.conf
<VirtualHost *:80>
    ServerName ${PBIN_IP}
    Redirect / https://${PBIN_IP}/
</VirtualHost>

<VirtualHost *:443>
    ServerName ${PBIN_IP}
    DocumentRoot /var/www/html/PrivateBin/
    
    SSLEngine on
    SSLCertificateFile /etc/ssl/certs/apache-selfsigned.crt
    SSLCertificateKeyFile /etc/ssl/private/apache-selfsigned.key
    
    ErrorLog \${APACHE_LOG_DIR}/privatebin-error.log
    CustomLog \${APACHE_LOG_DIR}/privatebin-access.log combined
    
    <Directory /var/www/html/PrivateBin>
        AllowOverride All
        Require all granted
    </Directory>
</VirtualHost>
EOF

log "Клонирование PrivateBin из Git..."
rm -rf /var/www/html/PrivateBin
git clone https://github.com/PrivateBin/PrivateBin.git /var/www/html/PrivateBin
chown -R www-data:www-data /var/www/html/PrivateBin
chmod -R 777 /var/www/html/PrivateBin
rm -f /var/www/html/index.html

log "Активация модулей и перезапуск Apache2..."
a2enmod ssl rewrite
a2ensite privatebin.conf
a2dissite 000-default.conf
systemctl reload apache2

log "--- Настройка PrivateBin завершена. Откройте https://privatebin.${DOMAIN} ---"