# 00 — پیش‌نیازهای مشترک

## نسخه مبنا

| جزء | نسخه انتخابی | توضیح |
|---|---|---|
| Ubuntu | 24.04 LTS amd64 | هر سه نود، با آخرین security update |
| Zabbix | 7.4.15 | آخرین stable تأییدشده در تاریخ تدوین؛ 8.0 در مستندات هنوز devel است |
| MariaDB | 11.4.13 Community LTS | دیتابیس انتخابی؛ MySQL همزمان نصب نشود |
| PHP | 8.3 از Ubuntu 24.04 | PHP-FPM |
| Nginx | بسته پشتیبانی‌شده Ubuntu 24.04 | آخرین security update مخزن داخلی |

7.4 شاخه LTS نیست؛ انتخاب آن مطابق درخواست آخرین stable است. تغییر بعدی شاخه/نسخه نیازمند بررسی سازگاری و بکاپ است. نسخه‌های کامل Debian شامل epoch و suffix از مخزن داخلی استخراج می‌شوند؛ suffix ساختگی در این داک نداریم.

## مقادیر موردنیاز

| مقدار | جایگزین |
|---|---|
| IP دیتابیس | 192.168.42.4 |
| IP نود B | 192.168.42.2 |
| IP نود C | 192.168.42.3 |
| IP مبدأ HAProxy (همه نودهای HA) | REPLACE_HAPROXY_IP |
| شبکه پراکسی‌ها | 192.168.42.5 و 192.168.42.6 |
| IP مدیر / شبکه مدیریت | REPLACE_ADMIN_CIDR |
| رمز دیتابیس | REPLACE_DB_PASSWORD |

برای رمز از رشته تصادفی طولانی hex استفاده کنید تا در SQL/PHP/کانفیگ escape مبهم نداشته باشد: `openssl rand -hex 32`. رمز واقعی را در git نگذارید. IPهای B/C ثابت باشند و هر دو frontend به IP هر دو سرور روی 10051 دسترسی داشته باشند.

## مخزن داخلی

دسترسی اینترنت مخزن، به معنی وجود بسته‌های Zabbix/MariaDB در آن نیست. مدیر Artifactory باید upstream رسمی Zabbix 7.4 برای Ubuntu noble و MariaDB 11.4 برای noble را با کلید امضای معتبر mirror/proxy کند. مسیر دقیق repository.iraneit.dev هنوز مشخص نیست؛ فایل sources فعال سازمان را حفظ کنید. از trusted=yes و allow-unauthenticated استفاده نکنید.

ابتدا Ubuntu، سپس بسته‌های vendor را بررسی کنید:

```bash
sudo -i
apt-get update
apt-cache policy mariadb-server mariadb-client mariadb-backup
apt-cache policy zabbix-server-mysql zabbix-frontend-php zabbix-nginx-conf zabbix-sql-scripts zabbix-agent2
```

اگر candidate نسخه موردنظر نیست، نصب را متوقف و mirror را اصلاح کنید. نصب پیش‌فرض mariadb-server از Ubuntu ممکن است 10.11 باشد، نه 11.4.

## آماده‌سازی OS روی A/B/C

```bash
apt-get install -y ca-certificates curl chrony openssl sysstat jq ripgrep
systemctl enable --now chrony
timedatectl set-timezone Asia/Tehran
chronyc tracking
lsblk -f
findmnt /var/lib/mysql
df -hT
```

hostnameهای اعلام‌شده: A=`EIT-ZBX-DB`، B=`EIT-ZBX-Pri`، C=`EIT-ZBX-HA`.

SSD دیتابیس باید قبل از نصب در /var/lib/mysql با mount دائمی آماده باشد؛ /etc/fstab مبتنی بر UUID و mount سالم بعد از reboot بررسی شود. این داک عمداً دستور format ندارد چون نام و وضعیت دیسک معلوم نیست. OS/log و DB ترجیحاً volume جدا داشته باشند. اگر تنها یک دیسک دارید برای OS، binlog، redo و فضای آزاد سهم در نظر بگیرید؛ کل 1 TB را history حساب نکنید. برای mount حیاتی DB از nofail استفاده نکنید.

CPU/RAM و clock ماشین‌ها را بررسی کنید؛ memory ballooning و overcommit شدید روی VM دیتابیس مناسب نیست. حدود 20٪ فضای دیسک آزاد نگه دارید. تنظیمات فایروال در داک شبکه آمده است.

## DNS و نام‌های قطعی

طبق تأیید شبکه، نام‌های کوتاه هر پنج نود بدون پسوند روی DNS داخلی resolve می‌شوند؛ پسوند دیگری لازم نیست. این‌ها نام DNS تک‌بخشی هستند. DBHost و NodeAddress با IPهای قطعی تنظیم شده‌اند. FQDN تأییدشده پنل `zabbix.iraneit.app` است و به HAProxy موجود اشاره می‌کند.

| نام | IP | نقش |
|---|---|---|
| EIT-ZBX-Pri | 192.168.42.2 | نود B |
| EIT-ZBX-HA | 192.168.42.3 | نود C |
| EIT-ZBX-DB | 192.168.42.4 | نود A |
| EIT-ZBX-Proxy01 | 192.168.42.5 | پراکسی اول |
| EIT-ZBX-Proxy02 | 192.168.42.6 | پراکسی دوم |

روی هر نود `hostnamectl set-hostname NAME` با نام همان نود اجرا شود. DNS داخلی مسیر اصلی resolve است و افزودن رکورد به /etc/hosts لازم نیست. فقط در صورت نیاز به fallback و با هماهنگی شبکه، رکوردهای زیر را بدون تکرار اضافه کنید؛ رکورد 127.0.1.1 متناقض برای نام همین نود اصلاح شود:

```text
192.168.42.2 EIT-ZBX-Pri
192.168.42.3 EIT-ZBX-HA
192.168.42.4 EIT-ZBX-DB
192.168.42.5 EIT-ZBX-Proxy01
192.168.42.6 EIT-ZBX-Proxy02
```

`getent hosts EIT-ZBX-Pri EIT-ZBX-HA EIT-ZBX-DB EIT-ZBX-Proxy01 EIT-ZBX-Proxy02` را بررسی کنید. دامنه پنل را در hosts به B یا C نگاشت نکنید؛ DNS آن باید HAProxy باشد. هر پنج نام باید از طریق DNS داخلی به IP جدول resolve شوند؛ resolver سازمانی روی هر نود تنظیم و با `resolvectl status` بررسی شود. IP مبدأ HAProxy، CIDR مدیریت و URI دقیق mirror هنوز نامشخص‌اند.
