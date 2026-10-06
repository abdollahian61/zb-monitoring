# 06 — نصب EIT-ZBX-Proxy01 و EIT-ZBX-Proxy02

IPها 192.168.42.5 و 192.168.42.6، نصب مستقیم روی Ubuntu 24.04. منابع CPU/RAM/دیسک پراکسی‌ها هنوز اعلام نشده‌اند؛ مقادیر کانفیگ نقطه شروع هستند و قبل از افزودن عمده هاست‌ها باید ظرفیت اندازه‌گیری شود. هر پراکسی Active است؛ Agentها Passive باقی می‌مانند.

## نصب روی هر دو پراکسی

پیش‌نیاز OS و mirror داک 00 را اجرا کنید. SQLite برای راه‌اندازی اولیه مستقل و بدون DB خارجی انتخاب شده است؛ حجم واقعی backlog و NVPS تعیین می‌کند برای تولید همین انتخاب کافی است یا DB اختصاصی نیاز داریم.

```bash
sudo -i
apt-get update
ZBX_VER=$(apt-cache madison zabbix-proxy-sqlite3 | awk '$3 ~ /(^|:)7\.4\.15([+~-]|$)/ {print $3; exit}')
test -n "$ZBX_VER" || { echo 'Proxy 7.4.15 missing from mirror'; exit 1; }
apt-get install -y zabbix-proxy-sqlite3="$ZBX_VER" zabbix-agent2="$ZBX_VER" zabbix-get="$ZBX_VER" fping sqlite3
systemctl stop zabbix-proxy
install -d -o zabbix -g zabbix -m 750 /var/lib/zabbix
```

روی Proxy01 فایل configs/zabbix-proxy-proxy01.conf و روی Proxy02 فایل configs/zabbix-proxy-proxy02.conf را در /etc/zabbix/zabbix_proxy.conf قرار دهید. SQLite در اولین start توسط پراکسی ساخته می‌شود؛ server.sql.gz را روی آن import نکنید.

```bash
chown root:zabbix /etc/zabbix/zabbix_proxy.conf
chmod 640 /etc/zabbix/zabbix_proxy.conf
systemctl enable --now zabbix-proxy
zabbix_proxy -V
tail -n 100 /var/log/zabbix/zabbix_proxy.log
```

## ثبت در پنل

در Data collection → Proxies دو پراکسی Active با نام دقیق EIT-ZBX-Proxy01 و EIT-ZBX-Proxy02 ثبت کنید. آدرس‌های مجاز اتصال به‌ترتیب 192.168.42.5 و 192.168.42.6 هستند (اگر NAT دارید IP دیده‌شده توسط server ملاک است). هاست‌ها را ابتدا به پراکسی مشخص assign کنید. دو پراکسی خودکار HA یکدیگر نیستند؛ Proxy group HA نیازمند گروه، تنظیم حداقل online، failover period و دسترسی هر دو پراکسی به هاست‌های گروه است. بدون بررسی network zone گروه مشترک ایجاد نشود.

Agent هاست‌های تحت پوشش Proxy01: Server=192.168.42.5؛ تحت Proxy02: Server=192.168.42.6. اگر گروه HA مشترک بعداً فعال شد، Server=192.168.42.5,192.168.42.6. ServerActive غیرفعال و templateها Passive باشند. برای مانیتور OS خود پراکسی توسط سرور مرکزی، Agent2 آن Server=192.168.42.2,192.168.42.3 و Hostname برابر نام همان پراکسی داشته باشد.

hybrid buffer با 128M RAM و offline retention تا 24 ساعت سقف زمانی پیکربندی است، نه تضمین ذخیره 24 ساعت؛ فضای SQLite و نرخ داده باید پایش شود. پیش از تولید TLS PSK/certificate مطابق سیاست سازمان روی پراکسی و پنل تنظیم شود؛ baseline ارتباط trusted داخلی است.

## آزمون

- last seen هر دو پراکسی تازه باشد و configuration sync بدون خطا انجام شود.
- یک هاست با Agent Passive، SNMP و HTTP روی هر پراکسی تست شود.
- قطع کوتاه server و بازیابی داده bufferشده بررسی شود.
- قطع خود پراکسی در حالت assign مستقل جمع‌آوری همان هاست‌ها را متوقف می‌کند؛ با server HA اشتباه گرفته نشود.
