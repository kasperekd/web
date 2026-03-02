# Автоматизированное развертывание стенда (ВМ 1-5)

**Вариант:** 18
**Студент:** oshlakov, Группа: ia232
**Домен:** oshlakov.ia232.local
**Локальная сеть:** 192.168.18.0/24

## Роли виртуальных машин
1. **gateway** (192.168.18.1) — Шлюз (NAT), ISC-DHCP-Server, Bind9 с динамическим обновлением зон. Имеет 2 сетевых адаптера (WAN и LAN).
2. **seafile** (192.168.18.4) — MariaDB, Nginx, Seafile 9.0.9.
3. **mail** (192.168.18.5) — iRedMail 1.6.2 (Nginx, OpenLDAP).
4. **wordpress** (192.168.18.6) — LAMP, WordPress.
5. **privatebin** (192.168.18.7) — Apache2, PHP, SSL (самоподписанный сертификат), PrivateBin.

## Инструкция по запуску
1. На все 5 ВМ установите чистую Ubuntu 24.04 Server.
2. Скопируйте папку `lab-setup` в `/opt/lab-setup` на каждую машину.
3. Убедитесь, что интерфейсы соответствуют заданным в `/opt/lab-setup/configs/lab-config.conf` (ens33/ens37).
4. Запустите скрипты от **root** (`sudo su`) в следующем порядке (дожидаясь окончания предыдущего):
   - На 1-й ВМ: `bash /opt/lab-setup/scripts/setup-gateway.sh`
   - На 2-й ВМ: `bash /opt/lab-setup/scripts/setup-seafile.sh`
   - На 3-й ВМ: `bash /opt/lab-setup/scripts/setup-mail.sh`
   - На 4-й ВМ: `bash /opt/lab-setup/scripts/setup-wordpress.sh`
   - На 5-й ВМ: `bash /opt/lab-setup/scripts/setup-privatebin.sh`

Скрипты являются идемпотентными (повторный запуск безопасен). В случае проблем читайте `/var/log/setup-<ROLE>.log`.