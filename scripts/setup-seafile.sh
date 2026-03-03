#!/bin/bash
ROLE="seafile"
source /opt/web/scripts/common.sh

log "--- Настройка Seafile ---"
setup_base_utils
set_hostname_and_hosts "seafile" "$SEAFILE_IP"
apply_netplan_static "$SEAFILE_IP"

log "Установка зависимостей Seafile и MariaDB..."
apt-get install -y -qq python3 python3-dev python3-setuptools python3-pip libmysqlclient-dev ldap-utils libldap2-dev python3.12-venv default-libmysqlclient-dev build-essential pkg-config libmemcached-dev libmysqlclient-dev mariadb-server nginx

python3 -m venv python-venv
source python-venv/bin/activate

pip3 install --timeout=3600 django==4.2.* future==1.0.* mysqlclient==2.2.* \
    pymysql pillow==10.4.* pylibmc captcha==0.6.* markupsafe==2.0.1 jinja2 sqlalchemy==2.0.* \
    psd-tools django-pylibmc django_simple_captcha==0.6.* djangosaml2==1.9.* pysaml2==7.3.* pycryptodome==3.20.* cffi==1.17.0 lxml python-ldap==3.4.* gevent==24.2.*

systemctl enable --now mariadb
mysql -u root -e "UPDATE mysql.user SET Password=PASSWORD('root') WHERE User='root'; FLUSH PRIVILEGES;" || true

log "Установка Seafile Server..."
mkdir -p /opt/seafile
cd /opt/seafile
if [ ! -f seafile-server_12.0.14_x86-64.tar.gz ]; then
    wget -q https://s3.eu-central-1.amazonaws.com/download.seadrive.org/seafile-server_12.0.14_x86-64.tar.gz
    tar -xzf seafile-server_12.0.14_x86-64.tar.gz
fi

# Если ранее не настраивали
if [ ! -d /opt/seafile/seafile-data ]; then
    cd seafile-server_12.0.14
    # Автоматическая настройка (имитация действий скрипта setup-seafile-mysql.sh)
    ./setup-seafile-mysql.sh auto -n "seafile" -i "$SEAFILE_IP" -p 8082 -d "/opt/seafile/seafile-data" -e 0 -u "root" -w "" -c "ccnet" -s "seafile" -b "seahub" || log "Предупреждение при автоустановке БД"
fi

chown -R root:root /opt/seafile

log "Настройка Nginx..."
cat <<EOF > /etc/nginx/sites-available/seafile.conf
server {
    listen ${SEAFILE_IP}:80;
    server_name seafile.${DOMAIN};
    location / {
        proxy_pass http://127.0.0.1:8000;
        proxy_set_header Host \$host;
        proxy_set_header X-Forwarded-For \$proxy_add_x_forwarded_for;
        proxy_set_header X-Real-IP \$remote_addr;
        proxy_buffering off;
    }
}
EOF
ln -sf /etc/nginx/sites-available/seafile.conf /etc/nginx/sites-enabled/
rm -f /etc/nginx/sites-enabled/default
systemctl restart nginx

log "Настройка Systemd автозапуска Seafile..."
cat <<EOF > /etc/systemd/system/seafile.service
[Unit]
Description=Seafile
After=mariadb.service network.target

[Service]
Type=forking
ExecStart=/opt/seafile/seafile-server-12.0.14/seafile.sh start
ExecStop=/opt/seafile/seafile-server-12.0.14/seafile.sh stop[Install]
WantedBy=multi-user.target
EOF

cat <<EOF > /etc/systemd/system/seahub.service
[Unit]
Description=Seafile Hub
After=seafile.service

[Service]
Type=forking
ExecStart=/opt/seafile/seafile-server-12.0.14/seahub.sh start
ExecStop=/opt/seafile/seafile-server-12.0.14/seahub.sh stop

[Install]
WantedBy=multi-user.target
EOF

systemctl daemon-reload
systemctl enable --now seafile
systemctl enable --now seahub

log "--- Настройка Seafile завершена. Аккаунт админа создается вручную при первом запуске seahub.sh ---"