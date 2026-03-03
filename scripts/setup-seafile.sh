#!/bin/bash
ROLE="seafile"
source /opt/web/scripts/common.sh

log "--- Настройка Seafile (Версия 12.0.14) ---"
setup_base_utils
set_hostname_and_hosts "seafile" "$SEAFILE_IP"
apply_netplan_static "$SEAFILE_IP"

SEAFILE_VERSION="12.0.14"
SEAFILE_TARBALL="seafile-server_${SEAFILE_VERSION}_x86-64.tar.gz"

log "Установка зависимостей (MariaDB, Memcached, Python)..."
apt-get install -y -qq python3 python3-setuptools python3-pip libmysqlclient-dev \
    mariadb-server nginx memcached libmemcached-dev pwgen rsync

log "Установка Python-пакетов (PEP 668 fix)..."
pip3 install --timeout=3600 --break-system-packages \
    django==4.2.* future==0.18.* mysqlclient==2.1.* pymysql pillow==10.2.* \
    pylibmc captcha==0.5.* markupsafe==2.0.1 jinja2 sqlalchemy==2.0.18 \
    psd-tools django-pylibmc django-simple-captcha==0.6.* pycryptodome==3.19.* \
    cffi==1.15.1 lxml python-ldap==3.4.3

log "Настройка MariaDB (Установка пароля 'root')..."
systemctl enable --now mariadb
# Надежный способ установить пароль для автоматического скрипта
mysql -e "ALTER USER 'root'@'localhost' IDENTIFIED BY 'root'; FLUSH PRIVILEGES;"

log "Подготовка директорий и скачивание..."
mkdir -p /opt/seafile
cd /opt/seafile

if [ ! -f "$SEAFILE_TARBALL" ]; then
    wget -q "https://s3.eu-central-1.amazonaws.com/download.seadrive.org/$SEAFILE_TARBALL"
    tar -xzf "$SEAFILE_TARBALL"
fi

# Создаем симлинк вручную на случай, если скрипт упадет
ln -sfn "seafile-server-${SEAFILE_VERSION}" seafile-server-latest

log "Запуск установки баз данных..."
cd "/opt/seafile/seafile-server-latest"

# В версии 12 флаг пароля root - это именно -w. 
# Если он выдает ошибку, используем передачу параметров через printf (самый надежный способ)
printf "seafile\n${SEAFILE_IP}\n8082\n/opt/seafile/seafile-data\n1\nlocalhost\n3306\nroot\nroot\nseafile\nseafile\nseafile\n" | ./setup-seafile-mysql.sh

# Проверяем, создался ли конфиг
if [ ! -d "/opt/seafile/conf" ]; then
    log "Конфиги не созданы автоматически. Создаю структуру вручную..."
    mkdir -p /opt/seafile/conf
    touch /opt/seafile/conf/seahub_settings.py
    touch /opt/seafile/conf/gunicorn.conf.py
fi

log "Генерация JWT_PRIVATE_KEY..."
JWT_KEY=$(pwgen -s 40 1)
CONF_FILE="/opt/web/configs/lab-config.conf" # для переменных
SEAHUB_CONF="/opt/seafile/conf/seahub_settings.py"

# Настройка seahub_settings.py
cat <<EOF > "$SEAHUB_CONF"
SECRET_KEY = "$(pwgen -s 40 1)"
JWT_PRIVATE_KEY = '$JWT_KEY'
DATABASES = {
    'default': {
        'ENGINE': 'django.db.backends.mysql',
        'NAME': 'seahub_db',
        'USER': 'seafile',
        'PASSWORD': 'seafile',
        'HOST': '127.0.0.1',
        'PORT': '3306',
        'OPTIONS': {
            'init_command': "SET sql_mode='STRICT_TRANS_TABLES'",
        }
    }
}
SERVICE_URL = 'http://seafile.${DOMAIN}'
FILE_SERVER_ROOT = 'http://seafile.${DOMAIN}/seafhttp'
CACHES = {
    'default': {
        'BACKEND': 'django_pylibmc.memcached.PyLibMCCache',
        'LOCATION': '127.0.0.1:11211',
    }
}
EOF

log "Настройка Nginx..."
cat <<EOF > /etc/nginx/sites-available/seafile.conf
server {
    listen 80;
    server_name seafile.${DOMAIN};
    proxy_set_header X-Forwarded-For \$remote_addr;

    location / {
        proxy_pass         http://127.0.0.1:8000;
        proxy_set_header   Host \$host;
        proxy_set_header   X-Real-IP \$remote_addr;
        proxy_set_header   X-Forwarded-For \$proxy_add_x_forwarded_for;
        proxy_set_header   X-Forwarded-Host \$server_name;
        client_max_body_size 0;
    }

    location /seafhttp {
        rewrite ^/seafhttp(.*)\$ \$1 break;
        proxy_pass http://127.0.0.1:8082;
        client_max_body_size 0;
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

log "Настройка Systemd..."
cat <<EOF > /etc/systemd/system/seafile.service
[Unit]
Description=Seafile
After=network.target mariadb.service

[Service]
Type=forking
Environment=JWT_PRIVATE_KEY=$JWT_KEY
ExecStart=/opt/seafile/seafile-server-latest/seafile.sh start
ExecStop=/opt/seafile/seafile-server-latest/seafile.sh stop
User=root
Group=root

[Install]
WantedBy=multi-user.target
EOF

cat <<EOF > /etc/systemd/system/seahub.service
[Unit]
Description=Seafile Hub
After=network.target seafile.service

[Service]
Type=forking
Environment=JWT_PRIVATE_KEY=$JWT_KEY
ExecStart=/opt/seafile/seafile-server-latest/seahub.sh start
ExecStop=/opt/seafile/seafile-server-latest/seahub.sh stop
User=root
Group=root

[Install]
WantedBy=multi-user.target
EOF

systemctl daemon-reload
systemctl enable --now seafile
# Seahub часто падает при первом запуске, если Seafile еще не поднялся. Даем паузу.
sleep 5
systemctl enable --now seahub

log "--- Настройка Seafile 12.0.14 завершена! ---"