#!/bin/bash
ROLE="seafile"
source /opt/web/scripts/common.sh

log "--- Настройка Seafile (Версия 12.0.14) ---"
setup_base_utils
set_hostname_and_hosts "seafile" "$SEAFILE_IP"
apply_netplan_static "$SEAFILE_IP"

SEAFILE_VERSION="12.0.14"
SEAFILE_TARBALL="seafile-server_${SEAFILE_VERSION}_x86-64.tar.gz"

log "Установка системных зависимостей (MariaDB, Memcached, Nginx, Python)..."
apt-get install -y -qq python3 python3-setuptools python3-pip libmysqlclient-dev \
    ldap-utils libffi-dev mariadb-server nginx memcached libmemcached-dev

log "Установка Python-библиотек для Seafile 12.x..."
# Флаг --break-system-packages обязателен в Ubuntu 24.04 для глобального pip
pip3 install --timeout=3600 --break-system-packages \
    django==4.2.* future==0.18.* mysqlclient==2.1.* pymysql pillow==10.2.* \
    pylibmc captcha==0.5.* markupsafe==2.0.1 jinja2 sqlalchemy==2.0.18 \
    psd-tools django-pylibmc django-simple-captcha==0.6.* pycryptodome==3.19.* \
    cffi==1.15.1 lxml python-ldap==3.4.3

log "Настройка MariaDB..."
systemctl enable --now mariadb
# Устанавливаем пароль root для БД (необходим для автоматического скрипта Seafile)
mysql -u root -e "ALTER USER 'root'@'localhost' IDENTIFIED BY 'root'; FLUSH PRIVILEGES;" || \
mysql -u root -e "UPDATE mysql.user SET Password=PASSWORD('root') WHERE User='root'; FLUSH PRIVILEGES;" || true

log "Скачивание и распаковка Seafile Server ${SEAFILE_VERSION}..."
mkdir -p /opt/seafile
cd /opt/seafile

if [ ! -f "$SEAFILE_TARBALL" ]; then
    wget -q "https://s3.eu-central-1.amazonaws.com/download.seadrive.org/$SEAFILE_TARBALL"
    tar -xzf "$SEAFILE_TARBALL"
fi

log "Автоматическая настройка баз данных Seafile..."
if [ ! -d "/opt/seafile/seafile-data" ]; then
    cd "/opt/seafile/seafile-server-${SEAFILE_VERSION}"
    # Скрипт auto сам создаст базы ccnet_db, seafile_db, seahub_db
    ./setup-seafile-mysql.sh auto \
        -n "seafile" \
        -i "${SEAFILE_IP}" \
        -p 8082 \
        -d "/opt/seafile/seafile-data" \
        -e 0 \
        -u "root" \
        -w "root"
    
    log "Настройка завершена. Передаем права пользователю $USER_NAME..."
    chown -R "$USER_NAME:$USER_NAME" /opt/seafile
else
    log "Директория seafile-data уже существует. Пропуск инициализации БД."
fi

log "Настройка JWT_PRIVATE_KEY для Seafile 12..."

apt-get install -y -qq pwgen

JWT_KEY=$(pwgen -s 40 1)

CONF_FILE="/opt/seafile/conf/seahub_settings.py"

if grep -q "JWT_PRIVATE_KEY" "$CONF_FILE"; then
    log "JWT_PRIVATE_KEY уже существует в конфиге."
else
    echo "" >> "$CONF_FILE"
    echo "JWT_PRIVATE_KEY = '$JWT_KEY'" >> "$CONF_FILE"
    log "JWT_PRIVATE_KEY успешно добавлен в $CONF_FILE"
fi


sed -i "s|SERVICE_URL =.*|SERVICE_URL = 'http://seafile.${DOMAIN}'|" "$CONF_FILE"
if ! grep -q "FILE_SERVER_ROOT" "$CONF_FILE"; then
    echo "FILE_SERVER_ROOT = 'http://seafile.${DOMAIN}/seafhttp'" >> "$CONF_FILE"
fi

for service in seafile seahub; do
    UNIT_FILE="/etc/systemd/system/${service}.service"
    if ! grep -q "Environment=JWT_PRIVATE_KEY" "$UNIT_FILE"; then
        sed -i "/\[Service\]/a Environment=JWT_PRIVATE_KEY=$JWT_KEY" "$UNIT_FILE"
    fi
done

systemctl daemon-reload
systemctl restart seafile seahub

log "Настройка Nginx..."
cat <<EOF > /etc/nginx/sites-available/seafile.conf
server {
    listen 80;
    server_name seafile.${DOMAIN} ${SEAFILE_IP};

    proxy_set_header X-Forwarded-For \$remote_addr;

    location / {
        proxy_pass         http://127.0.0.1:8000;
        proxy_set_header   Host \$host;
        proxy_set_header   X-Real-IP \$remote_addr;
        proxy_set_header   X-Forwarded-For \$proxy_add_x_forwarded_for;
        proxy_set_header   X-Forwarded-Host \$server_name;
        proxy_read_timeout  1200s;
        # Игнорировать предупреждения о размере загружаемых файлов
        client_max_body_size 0;
    }

    # Настройка для синхронизации файлов (SeafDAV / HttpSync)
    location /seafhttp {
        rewrite ^/seafhttp(.*)\$ \$1 break;
        proxy_pass http://127.0.0.1:8082;
        client_max_body_size 0;
        proxy_set_header   X-Forwarded-For \$proxy_add_x_forwarded_for;
        proxy_connect_timeout  36000s;
        proxy_read_timeout  36000s;
        proxy_send_timeout  36000s;
        send_timeout  36000s;
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
After=network.target mariadb.service

[Service]
Type=forking
ExecStart=/opt/seafile/seafile-server-latest/seafile.sh start
ExecStop=/opt/seafile/seafile-server-latest/seafile.sh stop
LimitNOFILE=10000

[Install]
WantedBy=multi-user.target
EOF

cat <<EOF > /etc/systemd/system/seahub.service
[Unit]
Description=Seafile Hub
After=network.target seafile.service

[Service]
Type=forking
ExecStart=/opt/seafile/seafile-server-latest/seahub.sh start
ExecStop=/opt/seafile/seafile-server-latest/seahub.sh stop

[Install]
WantedBy=multi-user.target
EOF

systemctl daemon-reload
systemctl enable --now seafile
systemctl enable --now seahub

log "--- Настройка Seafile 12.0.14 завершена! ---"
log "ВНИМАНИЕ: Для создания учетной записи администратора Seafile выполните команду:"
log "cd /opt/seafile/seafile-server-latest && sudo ./seahub.sh createsuperuser"