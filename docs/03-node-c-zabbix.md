# 03 — نود C: دومین Zabbix Server و وب

منابع 8 vCPU / 16 GiB / 200 GB. نود B و schema دیتابیس باید قبلاً آماده باشند.

## 1. بسته‌ها

مرحله 1 داک B را عیناً روی C اجرا کنید؛ تمام بسته‌ها همان Zabbix 7.4.15 هستند. سرویس زبیکس را تا نصب کانفیگ متوقف نگه دارید. **هیچ schema import یا CREATE DATABASE روی C اجرا نشود.** هر دو سرور و frontend به همان DB نود A وصل می‌شوند.

## 2. کانفیگ یکتا

فایل [zabbix-server-c.conf](../configs/zabbix-server-c.conf) را در `/etc/zabbix/zabbix_server.conf` قرار دهید؛ DB IP و رمز مشترک، C IP واقعی و HANodeName یکتا باشد.

```bash
sudo -i
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
tail -n 100 /var/log/zabbix/zabbix_server.log
```

در شرایط سالم و وقتی B قبلاً فعال است، C باید Standby شود. هر دو systemd service می‌توانند running باشند؛ running بودن به معنی Active بودن نیست. نقش را با ha_status بررسی کنید. این HA الزاماً primary ثابت B ندارد؛ پس از failover نود برگشتی معمولاً Standby می‌شود.

## 3. وب دوم

مرحله 4 داک B را روی C اجرا کنید؛ Nginx 8080، PHP pool و HTTPS offload یکسان هستند. فایل `/etc/zabbix/web/zabbix.conf.php` ایجادشده روی B را از مسیر امن به C منتقل کنید؛ DB و تنظیمات یکسان، بدون `$ZBX_SERVER` و `$ZBX_SERVER_PORT` ثابت. owner=root:www-data، mode=640.

```bash
php -l /etc/zabbix/web/zabbix.conf.php
php-fpm8.3 -t
nginx -t
systemctl restart php8.3-fpm nginx
curl -I -H 'Host: zabbix.iraneit.app' http://127.0.0.1:8080/
```

نیازی به wizard مجدد نیست. با login روی هر frontend صحت دسترسی DB را بررسی کنید. به‌خاطر sessionهای PHP محلی در HAProxy از cookie persistence استفاده می‌کنیم؛ در خرابی frontend ممکن است ورود مجدد لازم باشد.

## 4. Agent و تحویل

Agent2 را مانند داک B با Server شامل IP هر دو نود، ServerActive غیرفعال و Hostname=EIT-ZBX-HA تنظیم کنید. سپس service را restart کنید.

- یک Active و یک Standby در HA status.
- نسخه یکسان serverها، frontendها و schema.
- هر frontend به 3306 نود A و 10051 هر دو نود دسترسی دارد.
- هر دو backend وب در HAProxy سالم‌اند.
- تست قطع process و قطع کامل VM طبق داک عملیات انجام شود.
