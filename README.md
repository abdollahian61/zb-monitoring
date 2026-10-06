# راهنمای نصب Zabbix HA — EIT

تاریخ تدوین: 2026-10-06. نصب جدید و مستقیم روی Ubuntu Server 24.04 LTS، بدون کانتینر.

| نود | نقش | CPU | RAM | دیسک |
|---|---|---:|---:|---:|
| A | MariaDB اختصاصی | 16 vCPU | 32 GiB | 1 TB SSD |
| B | Zabbix Server + Nginx/PHP | 8 vCPU | 16 GiB | 200 GB |
| C | Zabbix Server + Nginx/PHP | 8 vCPU | 16 GiB | 200 GB |

700–800 هاست؛ حدود 50 هاست مستقیم و بقیه پشت پراکسی. Agentها Passive، پراکسی‌های پیشنهادی Active؛ Agent، SNMP و URL. History برابر 30 روز و Trends برابر 90 روز. پنل https://zabbix.iraneit.app پشت HAProxy موجود شبکه با TLS offload قرار می‌گیرد.

Zabbix Serverها از HA داخلی Active/Standby استفاده می‌کنند. هر دو وب‌فرانت‌اند همزمان سرویس می‌دهند. VIP/Keepalived روی B/C لازم نیست. دیتابیس تک‌نود است؛ HA سرورها خرابی دیتابیس را پوشش نمی‌دهد. HAProxy موجود باید خودش دسترس‌پذیری مناسب داشته باشد.

## ترتیب اجرا

1. [پیش‌نیازها و نسخه‌ها](docs/00-prerequisites.md)
2. [نود A: دیتابیس](docs/01-node-a-database.md)
3. [نود B: اولین Zabbix Server و import اولیه](docs/02-node-b-zabbix.md)
4. [نود C: دومین Zabbix Server](docs/03-node-c-zabbix.md)
5. [HAProxy، پراکسی و Agent](docs/04-network-haproxy-agents.md)
6. [نصب دو پراکسی](docs/06-proxies.md)
7. [تست پذیرش، ظرفیت، بکاپ و عملیات](docs/05-validation-operations.md)

فایل‌های نمونه در [configs](configs) قرار دارند. همه مقادیر `REPLACE_*` باید قبل از اجرا جایگزین شوند. این ریپو مستندات نصب است، نه اسکریپت اجرای خودکار. دستورات با دسترسی root و فقط روی ماشین‌های تازه اجرا شوند.

## اعتبارسنجی

نسخه و پارامترها با منابع رسمی بررسی شده‌اند؛ روی VM واقعی اجرا نشده‌اند. تعداد آیتم، NVPS و IOPS واقعی هنوز معلوم نیست، بنابراین تنظیمات ظرفیت نقطه شروع هستند، نه تضمین ظرفیت 800 هاست. IPهای پنج نود ثبت شده‌اند؛ IP HAProxy، پسوند DNS داخلی و مسیر دقیق Artifactory هنوز ارائه نشده‌اند.

## منابع

- [نسخه پایدار Zabbix 7.4.15](https://www.zabbix.com/release_notes)
- [نیازمندی‌های Zabbix 7.4](https://www.zabbix.com/documentation/7.4/en/manual/installation/requirements)
- [HA داخلی](https://www.zabbix.com/documentation/7.4/en/manual/concepts/server/ha)
- [پارامترهای سرور](https://www.zabbix.com/documentation/7.4/en/manual/appendix/config/zabbix_server)
- [نصب بسته‌ها](https://www.zabbix.com/documentation/7.4/en/manual/installation/install_from_packages)
- [MariaDB Q3 2026](https://mariadb.org/mariadb-server-12-3-11-8-11-4-and-10-11-q3-2026-maintenance-releases-and-goodbye-10-6/)
- [MariaDB system variables](https://mariadb.com/docs/server/server-management/variables-and-modes/server-system-variables)
- [MariaDB InnoDB variables](https://mariadb.com/docs/server/server-usage/storage-engines/innodb/innodb-system-variables)

## بررسی سه‌مرحله‌ای

نام‌ها و IPهای قطعی در configs/inventory.json ثبت شده‌اند؛ فایل inventory خودکار کانفیگ‌ها را تولید نمی‌کند، ابزار بررسی ناسازگاری را تشخیص می‌دهد. اجرای `python3 scripts/review.py` سه دور بررسی استاتیک نام/IP، کلیدهای کانفیگ، syntax بلوک‌های Bash، لینک‌های داک و توپولوژی را انجام می‌دهد. اجرای نصب، حل وابستگی بسته‌ها و Failover واقعی نیازمند VM هستند.

نتیجه بازبینی این نسخه: سه دور PASS؛ 17 بلوک Bash بررسی شد. موارد باقی‌مانده: رمز دیتابیس، IP HAProxy، شبکه مدیریت، مسیر دقیق mirror، پسوند DNS داخلی و منابع پراکسی‌ها. برای FQDN داخلی مقدار ساختگی ثبت نشده است.
