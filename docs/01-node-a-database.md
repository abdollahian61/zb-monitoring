# 01 — نود A: MariaDB

منابع: 16 vCPU / 32 GiB / 1 TB SSD. فقط MariaDB و ابزار بکاپ؛ زبیکس سرور/وب اینجا نصب نشود. پیش‌نیازها و mount را ابتدا انجام دهید.

## 1. نصب نسخه دقیق

```bash
sudo -i
apt-get update
MDB_VER=$(apt-cache madison mariadb-server | awk '$3 ~ /(^|:)11\.4\.13([+~-]|$)/ {print $3; exit}')
test -n "$MDB_VER" || { echo 'MariaDB 11.4.13 is missing from mirror'; exit 1; }
apt-get install -y mariadb-server="$MDB_VER" mariadb-client="$MDB_VER" mariadb-backup="$MDB_VER"
systemctl stop mariadb
```

اگر suffix نسخه client/backup متفاوت باشد، نسخه کامل هر بسته را جدا با madison بردارید. حل وابستگی apt باید بدون downgrade غیرمنتظره باشد.

## 2. تنظیمات

فایل [mariadb.cnf](../configs/mariadb.cnf) را بعد از جایگزینی DB IP در `/etc/mysql/mariadb.conf.d/60-zabbix.cnf` قرار دهید.

```bash
install -d -o mysql -g mysql -m 750 /var/log/mysql
chmod 644 /etc/mysql/mariadb.conf.d/60-zabbix.cnf
systemctl enable --now mariadb
systemctl status mariadb --no-pager
mariadb -e "SELECT VERSION(); SHOW VARIABLES WHERE Variable_name IN ('innodb_buffer_pool_size','thread_pool_size','innodb_read_io_threads','innodb_write_io_threads','binlog_expire_logs_seconds');"
journalctl -u mariadb -n 100 --no-pager
ss -lntp | rg ':3306'
```

24 GiB buffer pool برای دیتابیس اختصاصی؛ باقی RAM برای OS، اتصال‌ها، sort/temp و بکاپ. thread_pool_size=16 تعداد گروه‌های thread pool است، نه محدودیت قطعی تعداد threadهای OS. read/write IO threads هرکدام 8 و purge threads برابر 4 نقطه شروع هستند. IO capacity به توان واقعی SSD/استوریج وابسته است؛ اگر latency افزایش یافت با iostat اندازه‌گیری و اصلاح شود. MariaDB گزینه‌های MySQL مانند innodb_redo_log_capacity را ندارد؛ این کانفیگ مخصوص MariaDB 11.4 است.

binlog هفت روز برای PITR فعال است؛ بکاپ و فضای binlog باید مانیتور شوند. flush_log_at_trx_commit=1 و sync_binlog=1 برای دوام داده انتخاب شده‌اند.

## 3. ایجاد DB و حساب‌ها

با `sudo mariadb` وارد شوید و این SQL را با IP و رمز واقعی اجرا کنید؛ از password روی command line استفاده نکنید:

```sql
CREATE DATABASE zabbix CHARACTER SET utf8mb4 COLLATE utf8mb4_bin;
CREATE USER 'zabbix'@'192.168.42.2' IDENTIFIED BY 'REPLACE_DB_PASSWORD';
CREATE USER 'zabbix'@'192.168.42.3' IDENTIFIED BY 'REPLACE_DB_PASSWORD';
GRANT ALL PRIVILEGES ON zabbix.* TO 'zabbix'@'192.168.42.2';
GRANT ALL PRIVILEGES ON zabbix.* TO 'zabbix'@'192.168.42.3';
SELECT User,Host FROM mysql.user;
```

حساب بدون % و بدون privilege سراسری است. نصب import و upgrade به دسترسی DDL روی همین DB نیاز دارد. schema فقط یک‌بار، در مرحله نود B import می‌شود؛ در نود A/C دوباره import نکنید. قبل از import روی B، در نشست root دیتابیس `SHOW GLOBAL VARIABLES LIKE 'log_bin_trust_function_creators';` را ثبت کنید؛ برای import دارای trigger با binlog فعال، `SET GLOBAL log_bin_trust_function_creators=1;` اجرا و بعد از اتمام import با `SET GLOBAL log_bin_trust_function_creators=0;` به مقدار قبلی (اگر قبلاً صفر بوده) برگردانید. اگر import با خطای binary logging/trigger privilege مواجه شد، مقدار فعلی log_bin_trust_function_creators را ثبت، موقتاً 1 کنید و بلافاصله بعد از import به مقدار قبلی برگردانید؛ دائمی رها نشود.

پورت 3306 فقط از B/C و مسیر بکاپ مصوب مجاز باشد. ارتباط داخلی DB در این baseline بدون TLS است و باید در شبکه محدود باشد؛ اگر سیاست سازمان TLS داخلی می‌خواهد، قبل از go-live گواهی CA و verify روی server/frontend تنظیم شود.

## 4. تحویل نود A

- نسخه دقیق 11.4.13 و service سالم؛ reboot و mount بررسی شده.
- DB خالی و دو حساب IP-specific ایجاد شده.
- 3306 از B/C قابل اتصال و از شبکه غیرمجاز مسدود.
- لاگ slow با logrotate سازمانی چرخش دارد؛ binlog با حذف دستی فایل پاک نشود.
- backup خارج از همین VM مطابق داک عملیات آماده شود.

در بازبینی، innodb_flush_method منسوخ با چهار گزینه buffering/write-through مخصوص MariaDB جدید جایگزین شد؛ دوام commit همچنان با innodb_flush_log_at_trx_commit=1 و sync_binlog=1 برقرار است.
