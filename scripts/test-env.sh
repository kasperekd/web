#!/bin/bash

# Устанавливаем роль (нужна для переменной LOG_FILE внутри common.sh)
ROLE="test-debug"

# 1. Проверка наличия папок
echo "--- ПРОВЕРКА ПУТЕЙ ---"
[ -d "/opt/lab-setup" ] && echo "[OK] Директория /opt/lab-setup существует" || echo "[!!] Директория /opt/lab-setup НЕ НАЙДЕНА"

# 2. Пытаемся подключить common.sh по абсолютному пути
COMMON_PATH="/opt/lab-setup/scripts/common.sh"

if [ -f "$COMMON_PATH" ]; then
    echo "[OK] Файл common.sh найден по пути $COMMON_PATH"
    
    # ПОПЫТКА ПОДКЛЮЧЕНИЯ
    source "$COMMON_PATH"
    
    if [ $? -eq 0 ]; then
        echo "[OK] common.sh успешно загружен (source)"
    else
        echo "[!!] Ошибка при выполнении source $COMMON_PATH"
    fi
else
    echo "[!!] Файл common.sh НЕ НАЙДЕН в $COMMON_PATH"
    exit 1
fi

echo ""
echo "--- ПРОВЕРКА ФУНКЦИЙ ИЗ COMMON ---"
# Вызываем функцию log из common.sh
log "Тестовый вызов функции log() прошел успешно." && echo "[OK] Функция log() видна" || echo "[!!] Функция log() НЕ ВИДНА"

echo ""
echo "--- ТЕКУЩИЕ КОНФИГИ (из lab-config.conf) ---"
echo "VARIANT:    $VARIANT"
echo "DOMAIN:     $DOMAIN"
echo "GW_IP:      $GW_IP"
echo "LAN_SUBNET: $LAN_SUBNET"
echo "USER:       $USER_NAME"

echo ""
echo "--- ПРОВЕРКА ПРАВ ---"
if [ "$EUID" -ne 0 ]; then
  echo "[!!] Скрипт запущен НЕ от root. Многие функции (apt, netplan) не сработают."
else
  echo "[OK] Запущено от root."
fi