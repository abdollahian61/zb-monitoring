# 02 — نود B: Zabbix Server و وب

منابع 8 vCPU / 16 GiB / 200 GB. نود A باید آماده باشد. دستورات root هستند.

## 1. نصب بسته‌های هم‌نسخه

```bash
sudo -i
apt-get update
ZBX_VER=$(apt-cache madison zabbix-server-mysql | awk '$3 ~ /(^|:)7\.4\.15([+~-]|$)/ {print $3; exit}')
test -n "$ZBX_VER" || { echo 'Zabbix 7.4.15 is missing from mirror'; exit 1; }
apt-get install -y zabbix-server-mysql="$ZBX_VER" zabbix-frontend-php="$ZBX_VER" zabbix-nginx-conf="$ZBX_VER" zabbix-sql-scripts="$ZBX_VER" zabbix-agent2="$ZBX_VER" zabbix-get="$ZBX_VER" nginx php8.3-fpm php8.3-mysql mariadb-client fping
systemctl stop zabbix-server
zabbix_server -V
dpkg-query -W 'zabbix*'
```

در صورت suffix متفاوت، نسخه هر بسته را جدا استخراج کنید؛ همه componentهای Zabbix باید 7.4.15 باشند. ابزارهای `rg` در دستورات داک از بسته ripgrep هستند: `apt-get install -y ripgrep`.

## 2. import فقط یک‌بار

قبل از import، خالی‌بودن DB را بررسی کنید:

```bash
mariadb -h 192.168.42.4 -u zabbix -p -e "SELECT COUNT(*) AS tables_count FROM information_schema.tables WHERE table_schema='zabbix';"
```

فقط اگر tables_count صفر است اجرا کنید. استفاده از فایل موقت 0600 برای واردکردن رمز از تداخل stdin با prompt جلوگیری می‌کند:

```bash
umask 077
cat > /root/zabbix-import.cnf <<'EOF'
[client]
host=192.168.42.4
user=zabbix
password=REPLACE_DB_PASSWORD
EOF
set -o pipefail
zcat /usr/share/zabbix/sql-scripts/mysql/server.sql.gz | mariadb --defaults-extra-file=/root/zabbix-import.cnf --default-character-set=utf8mb4 zabbix
IMPORT_RC=$?
rm -f /root/zabbix-import.cnf
test "$IMPORT_RC" -eq 0 || { echo 'Schema import failed: investigate before starting'; exit 1; }
mariadb -h 192.168.42.4 -u zabbix -p zabbix -e 'SELECT * FROM dbversion; SHOW TABLES;'
```

اگر import نیمه‌تمام شد، دوباره روی همان DB اجرا نکنید؛ خطا را بررسی و فقط برای نصب تازه و پس از تأیید نبود داده، DB خالی جدید بسازید. مراحل privilege موقت binlog در داک A آمده‌اند.

## 3. کانفیگ سرور

فایل [zabbix-server-b.conf](../configs/zabbix-server-b.conf) را جایگزین `/etc/zabbix/zabbix_server.conf` کنید؛ IPها و رمز را اصلاح کنید. این فایل جایگزین کامل است تا پارامتر تکراری نداشته باشیم.

```bash
chown root:zabbix /etc/zabbix/zabbix_server.conf
chmod 640 /etc/zabbix/zabbix_server.conf
install -d /etc/systemd/system/zabbix-server.service.d
cat > /etc/systemd/system/zabbix-server.service.d/limits.conf <<'EOF'
[Service]
LimitNOFILE=65536
EOF
systemctl daemon-reload
systemctl enable --now zabbix-server
zabbix_server -R ha_status
journalctl -u zabbix-server -n 100 --no-pager
tail -n 100 /var/log/zabbix/zabbix_server.log
```

در این مرحله B باید Active باشد. پارامتر HANodeName با نود C یکتا است؛ NodeAddress آدرس واقعی نود است، نه HAProxy.

## 4. وب Nginx / PHP

در `/etc/zabbix/nginx.conf` خطوط listen و server_name نمونه را فعال و به این مقادیر تغییر دهید:

```nginx
listen 8080;
server_name zabbix.iraneit.app;
```

بقیه locationهای بسته رسمی، root و fastcgi_pass را حفظ کنید. مسیر واقعی فایل فعال را با `nginx -T` بررسی کنید. 8080 فقط از HAProxy/مدیریت مجاز است. PHP pool بسته در `/etc/zabbix/php-fpm.conf` را حفظ کنید؛ اگر ساختار مسیر متفاوت است با `dpkg -L zabbix-nginx-conf` پیدا کنید. مقادیر pool:

```ini
pm = dynamic
pm.max_children = 20
pm.start_servers = 4
pm.min_spare_servers = 4
pm.max_spare_servers = 8
php_value[date.timezone] = Asia/Tehran
php_value[max_execution_time] = 300
php_value[memory_limit] = 256M
php_value[post_max_size] = 16M
php_value[upload_max_filesize] = 16M
php_value[max_input_time] = 300
php_value[session.cookie_secure] = 1
php_value[session.cookie_httponly] = 1
```

برای اطلاع PHP از HTTPS بیرونی، داخل location مربوط به PHP و **بعد از include fastcgi_params** اضافه کنید:

```nginx
fastcgi_param HTTPS on;
fastcgi_param SERVER_PORT 443;
```

این backend اختصاصی فقط برای HTTPS offload است؛ درخواست عمومی مستقیم HTTP به آن مجاز نباشد. برای pool socket همان fastcgi_pass فایل رسمی را استفاده کنید.

```bash
php-fpm8.3 -t
nginx -t
systemctl enable --now php8.3-fpm nginx
systemctl restart php8.3-fpm nginx
curl -I -H 'Host: zabbix.iraneit.app' http://127.0.0.1:8080/
```

## 5. frontend و اولین ورود

پس از تنظیم HAProxy، wizard را از HTTPS دامنه باز کنید. DB type=MySQL، host=IP نود A، port=3306، database=zabbix، user=zabbix و رمز انتخابی. Timezone=Asia/Tehran.

فایل خروجی `/etc/zabbix/web/zabbix.conf.php` را بررسی کنید؛ برای HA نباید آدرس/پورت ثابت server تعریف شده باشد. خطوط `$ZBX_SERVER` و `$ZBX_SERVER_PORT` را حذف کنید (نام نمایشی ZBX_SERVER_NAME مشکلی ندارد). frontend نود فعال را از دیتابیس می‌خواند.

```bash
chown root:www-data /etc/zabbix/web/zabbix.conf.php
chmod 640 /etc/zabbix/web/zabbix.conf.php
php -l /etc/zabbix/web/zabbix.conf.php
```

اولین ورود Admin/zabbix است؛ بلافاصله رمز را تغییر دهید، MFA و حساب‌های نام‌دار با نقش مناسب تعریف کنید. فایل کانفیگ حاوی رمز را در git قرار ندهید.

## 6. Agent2 خود نود

در `/etc/zabbix/zabbix_agent2.conf` مقدارهای فعال را اصلاح کنید (تکراری نگذارید):

```ini
Server=192.168.42.2,192.168.42.3
Hostname=EIT-ZBX-Pri
```

ServerActive را خالی/کامنت کنید. از template نوع passive مانند Linux by Zabbix agent استفاده کنید. سپس `systemctl enable --now zabbix-agent2` و `systemctl restart zabbix-agent2`. مانیتورینگ DB/OS نود A و C هم مطابق همین دسترسی مبدأ تنظیم شود.
