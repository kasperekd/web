#!/bin/bash
ROLE="wordpress"
source /opt/lab-setup/scripts/common.sh

log "--- Настройка WordPress (LAMP) ---"
setup_base_utils
set_hostname_and_hosts "wordpress" "$WP_IP"
apply_netplan_static "$WP_IP"

log "Установка LAMP (Apache2, MariaDB, PHP)..."
apt-get install -y -qq apache2 mariadb-server php php-mysql libapache2-mod-php wget tar

log "Настройка MariaDB для WordPress..."
systemctl enable --now mariadb
mysql -u root -e "CREATE DATABASE IF NOT EXISTS wordpress CHARACTER SET utf8 COLLATE utf8_bin;"
mysql -u root -e "CREATE USER IF NOT EXISTS 'author'@'localhost' IDENTIFIED BY 'P@ssw0rd';"
mysql -u root -e "GRANT ALL PRIVILEGES ON wordpress.* TO 'author'@'localhost';"
mysql -u root -e "FLUSH PRIVILEGES;"

log "Загрузка и конфигурация WordPress..."
cd /tmp
if[ ! -f latest-ru_RU.tar.gz ]; then
    wget -q https://ru.wordpress.org/latest-ru_RU.tar.gz
    tar xzvf latest-ru_RU.tar.gz
fi

rm -rf /var/www/html/*
rsync -aP /tmp/wordpress/ /var/www/html/
chown -R www-data:www-data /var/www/html
chmod -R 755 /var/www/html

cp /var/www/html/wp-config-sample.php /var/www/html/wp-config.php
sed -i "s/database_name_here/wordpress/" /var/www/html/wp-config.php
sed -i "s/username_here/author/" /var/www/html/wp-config.php
sed -i "s/password_here/P@ssw0rd/" /var/www/html/wp-config.php

echo "ServerName localhost" >> /etc/apache2/apache2.conf
systemctl restart apache2

log "--- Настройка WordPress завершена. Откройте http://wordpress.${DOMAIN} ---"