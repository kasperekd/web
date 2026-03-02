#!/bin/bash
ROLE="mail"
source /opt/web/scripts/common.sh

log "--- Настройка iRedMail ---"
setup_base_utils
set_hostname_and_hosts "mail" "$MAIL_IP"
apply_netplan_static "$MAIL_IP"

cat <<EOF > /etc/hosts
127.0.0.1 localhost
${MAIL_IP} mail.${DOMAIN} mail
EOF

log "Скачивание iRedMail 1.7.4..."
cd /root
if [ ! -f 1.7.4.tar.gz ]; then
    wget -q https://github.com/iredmail/iRedMail/archive/refs/tags/1.7.4.tar.gz
    tar xvf 1.7.4.tar.gz
fi
cd iRedMail-1.7.4

log "Автоматизация установки iRedMail..."
# Создаем файл ответов для автоматической установки без GUI
cat <<EOF > config
export USE_DEFAULT_SETTINGS=NO
export BACKEND='ldap'
export FIRST_DOMAIN='${DOMAIN}'
export FIRST_DOMAIN_ADMIN_PASSWORD='Password123!'
export LDAP_SUFFIX='dc=${USER_NAME},dc=${GROUP_NAME},dc=local'
export LDAP_ROOTPW='Password123!'
export MYSQL_ROOT_PASSWORD='Password123!'
export MYSQL_GRANT_HOST='localhost'
export WEBSERVER='nginx'
export SOGO_USE_SQLITE='YES'
EOF

export AUTO_USE_EXISTING_CONFIG_FILE=y
export AUTO_INSTALL_WITHOUT_CONFIRM=y
export AUTO_CLEANUP_REMOVE_SENDMAIL=y
export AUTO_CLEANUP_REPLACE_FIREWALL_RULES=n

log "Запуск скрипта установки iRedMail (может занять 10-15 минут)..."
bash iRedMail.sh

log "--- Настройка iRedMail завершена (УЗ: postmaster@${DOMAIN} / Password123!) ---"