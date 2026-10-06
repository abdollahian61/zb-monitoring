# 05 — پذیرش و عملیات

## 1. نگهداری داده

در Administration → Housekeeping، Internal housekeeping برای History و Trends فعال و Override item history period=30d و Override item trend period=90d شود. این override روی آیتم‌ها اعمال می‌شود؛ آیتم‌های log/text/string trend ندارند. ثبت screenshot/خروجی تنظیمات در تحویل انجام شود. در baseline، housekeeping داخلی فعال است و partitioning اتوماتیک اضافه نشده است؛ اگر بار حذف سنگین شد، طرح partitioning جدا با تست سازگاری تهیه شود. MaxHousekeeperDelete تعداد delete هر task است، نه سقف کل حذف دیتابیس.

## 2. تیونینگ اولیه سرور

| پارامتر | مقدار | دلیل |
|---|---:|---|
| StartAgentPollers | 2 | Agent Passive async برای حدود 50 هاست مستقیم |
| StartSNMPPollers | 2 | SNMP async مستقیم |
| StartHTTPAgentPollers | 2 | HTTP agent items |
| StartHTTPPollers | 4 | web scenarios؛ با HTTP agent متفاوت است |
| StartPollers | 5 | سایر pollهای همزمان کلاسیک |
| StartTrappers | 8 | پراکسی‌های Active و senderها |
| StartPreprocessors | 8 | نقطه شروع متناسب با 8 CPU |
| StartDBSyncers | 4 | پیش‌فرض؛ افزایش کورکورانه باعث فشار DB می‌شود |
| CacheSize | 512M | config همه هاست‌ها، حتی پشت پراکسی |
| HistoryCacheSize | 256M | داده ورودی قبل از write |
| HistoryIndexCacheSize | 128M | ایندکس history cache |
| TrendCacheSize | 128M | trend processing |
| ValueCacheSize | 512M | ارزیابی trigger |

بار poll عمده روی پراکسی‌هاست، اما preprocessing، trigger و DB write مرکزی می‌مانند. تعداد هاست به‌تنهایی ظرفیت را تعیین نمی‌کند. هر نود سرور باید کل بار Active را تحمل کند؛ ظرفیت CPU دو نود جمع نمی‌شود.

با templateهای رسمی Zabbix server health و OS، در 24–72 ساعت بار واقعی NVPS، queue، process busy، cache free، unsupported items، disk latency و slow queries را ثبت کنید. busy پایدار بالای 75٪ یا queue رو به رشد نیازمند بررسی است؛ ابتدا endpoint latency و DB bottleneck بررسی شود. cache free کمتر از حدود 20٪ نیازمند افزایش تدریجی همان cache است. StartDBSyncers را فقط با شواهد اندازه‌گیری تغییر دهید. آیتم‌های dependent داده master را reuse می‌کنند؛ interval همه آیتم‌ها را بی‌دلیل 1s نکنید.

## 3. ظرفیت دیسک

برای numeric history برآورد اولیه رسمی حدود 90 بایت هر value است (نوع داده، index و storage واقعی مؤثرند):

`History bytes ≈ NVPS × 86400 × 30 × 90`

| NVPS فرضی | History سی‌روزه، decimal GB |
|---:|---:|
| 1000 | 233 |
| 2000 | 467 |
| 3000 | 700 |

این اعداد شامل trend، events، log/text، binlog، redo، بکاپ و فضای آزاد نیستند. Trends تقریباً numeric item count × 24 × 90 × 90 bytes، تنها برای آیتم‌هایی که واقعاً trend می‌سازند. حجم data+index را روزانه از information_schema ثبت و رشد واقعی را extrapolate کنید. 1 TB تضمین کافی‌بودن برای بار نامشخص نیست؛ اگر حدود 70–80٪ ظرفیت پیش‌بینی شد، قبل از پرشدن دیسک retention/interval/storage بازبینی شود.

```sql
SELECT table_name, ROUND((data_length+index_length)/1024/1024/1024,2) AS gib
FROM information_schema.tables WHERE table_schema='zabbix'
ORDER BY data_length+index_length DESC;
```

## 4. تست Failover

1. روی B/C `zabbix_server -R ha_status` و یک Active/یک Standby را ثبت کنید. frontend از DB نود فعال را کشف کند.
2. روی نود Active `systemctl stop zabbix-server`؛ نقش نود دیگر و ورود داده جدید را بررسی کنید. stop کنترل‌شده با خرابی ناگهانی زمان متفاوتی دارد.
3. سرویس قبلی را start کنید؛ نباید دو Active مشاهده شود.
4. خرابی ناگهانی VM Active را در پنجره تست شبیه‌سازی کنید؛ زمان تا takeover و data gap را ثبت کنید. failover delay پیش‌فرض حدود 1 دقیقه است؛ failover بدون gap وعده داده نمی‌شود. با runtime `zabbix_server -R ha_set_failover_delay=1m` می‌توان مقدار را صریح تعیین کرد؛ حداقل‌ها و رفتار نسخه را در منابع رسمی بررسی کنید.
5. nginx روی یک نود را stop کنید؛ دامنه از frontend دیگر قابل ورود باشد (ممکن است session نیازمند login مجدد شود).
6. روی هر frontend هم اتصال به نود Active B و هم Active C را تست کنید.
7. پراکسی آزمایشی Active با هر دو server address و یک هاست Passive اضافه کنید؛ takeover و backfill داده bufferشده را بررسی کنید.
8. یک Agent، یک SNMP و یک URL مستقیم را تست کنید. سپس نمونه پشت پراکسی.

برای HA، صرف TCP-open بودن/پینگ کافی نیست. خرابی نود A کل جمع‌آوری مرکزی را متوقف می‌کند؛ پراکسی‌ها فقط تا ظرفیت buffer می‌توانند داده نگه دارند.

## 5. بکاپ و بازیابی

پیشنهاد عملیاتی: daily physical full با mariadb-backup هم‌نسخه و archive مداوم binlog به مقصد خارج VM. RPO/RTO باید با سازمان تعیین شود؛ نگهداری binlog محلی هفت‌روزه به‌تنهایی بکاپ نیست. مقصد بکاپ جدا از volume دیتابیس باشد. نمونه اجرا روی A با root socket محلی و مقصد mount شده:

```bash
sudo -i
BACKUP_ROOT=/mnt/zabbix-backup
mountpoint -q "$BACKUP_ROOT" || { echo 'Backup mount missing'; exit 1; }
BACKUP_DIR="$BACKUP_ROOT/$(date +%F-%H%M%S)"
install -d -m 700 "$BACKUP_DIR"
mariadb-backup --backup --user=root --target-dir="$BACKUP_DIR"
mariadb-backup --prepare --target-dir="$BACKUP_DIR"
```

اگر root socket authentication سازمان تغییر کرده، حساب backup اختصاصی با privilegeهای رسمی همان نسخه و فایل credential محدود ایجاد کنید. prepare روی کپی بکاپ انجام شود؛ کد خروجی و completeness باید ثبت شود. از نگهداری رمز CLI خودداری کنید. ذخیره backup encrypted، انتقال خارج VM و retention سازمانی تعریف شود؛ حذف خودکار در این داک ندارد.

بازیابی ابتدا روی VM ایزوله با MariaDB 11.4.13: سرویس خاموش، datadir خالی مقصد، `mariadb-backup --copy-back --target-dir=...`، مالک mysql:mysql، start و بررسی schema/countها. این دستور فقط روی مقصد بازیابی اجرا شود و با datadir تولیدی اجرا نشود. سپس آزمون frontend و serverها با آدرس محیط تست. RTO واقعی ثبت شود. فایل‌های /etc/zabbix، /etc/mysql، Nginx/PHP و HAProxy و package manifest هم با رمزگذاری بکاپ شوند.

## 6. چک‌های تحویل و upgrade

```bash
zabbix_server -V
zabbix_server -R ha_status
systemctl is-active zabbix-server nginx php8.3-fpm
nginx -t
php-fpm8.3 -t
```

هر نود manifest `dpkg-query -W` داشته باشد. برای جلوگیری از drift بسته‌های Zabbix/MariaDB را پس از نصب در apt-mark hold قرار دهید؛ security updateها در پنجره maintenance با unhold و برنامه تست اعمال شوند، hold دائمی بدون رسیدگی نباشد. PHP/Nginx/OS patch طبق سیاست سازمان.

ارتقای شاخه/major زبیکس rolling فرض نشود؛ قبل از upgrade بکاپ قابل restore و رویه HA نسخه مقصد مطالعه شود. هر دو server و frontend با یک schema سازگار باشند. تست restore و Failover جزء پذیرش نهایی هستند.
