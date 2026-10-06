# 04 — شبکه، HAProxy و پراکسی‌ها

## جریان دسترسی

| مبدأ | مقصد | پورت | کاربرد |
|---|---|---|---|
| کاربران مجاز | HAProxy | TCP 443 | پنل HTTPS |
| HAProxy | B/C | TCP 8080 | وب؛ TLS offload در HAProxy |
| B/C | A | TCP 3306 | MariaDB |
| B/C frontend | B/C server | TCP 10051 | ارتباط با نود Active |
| پراکسی Active | B و C | TCP 10051 | دریافت config / ارسال داده |
| B/C | 50 هاست مستقیم | TCP 10050 | Passive Agent |
| پراکسی‌ها | هاست‌های خود | TCP 10050 | Passive Agent |
| سرور/پراکسی مسئول | تجهیزات شبکه | UDP 161 | SNMP polling |
| سرور/پراکسی مسئول | URLها | TCP 80/443 یا پورت سرویس | HTTP checks |
| سرور/پراکسی مسئول | هاست‌ها | ICMP | ping در صورت استفاده |
| A/B/C | DNS/NTP/mirror | پورت مصوب | DNS، زمان و نصب |

Agent Passive به 10051 اتصال خروجی نیاز ندارد؛ 10050 روی Agent برای collector باز می‌شود. SNMP trap روی UDP 162 جزو این طرح نیست. اگر بعداً اضافه شد مسیر و process جدا دارد. SSH فقط از مدیریت؛ جدول باید روی فایروال شبکه/host اعمال شود، قبل از فعال‌کردن firewall دسترسی SSH را حفظ کنید.

## HAProxy موجود

DNS دامنه به آدرس سرویس HAProxy اشاره کند. ACL و backend فایل [haproxy.cfg](../configs/haproxy.cfg) را به کانفیگ موجود اضافه کنید؛ فایل کامل فعلی را بازنویسی نکنید. frontend در mode http و دارای termination گواهی موجود باشد. برای Host با port اختیاری، ACL اضافی مناسب اضافه کنید.

```bash
haproxy -c -f /etc/haproxy/haproxy.cfg
systemctl reload haproxy
curl -I https://zabbix.iraneit.app/
```

health check وب سلامت HTTP را بررسی می‌کند؛ سلامت DB و Zabbix server باید جدا مانیتور شود. روی standby بودن Zabbix Server به معنی down کردن backend وب نیست؛ هر دو frontend فعال‌اند. این طرح backend TCP عمومی برای 10051 ندارد.

## پراکسی‌های فاز بعد

Passive بودن Agent مستقل از Active بودن پراکسی است. پیشنهاد این پروژه: ProxyMode=0 (Active) و هر دو آدرس HA server با **semicolon**:

```ini
ProxyMode=0
Server=REPLACE_B_IP:10051;REPLACE_C_IP:10051
Hostname=eit-zbx-proxy01
```

Hostname باید دقیقاً با پراکسی ثبت‌شده در UI برابر باشد. نسخه پراکسی همان 7.4.15 باشد؛ DB/buffer، HA گروه پراکسی و sizing آن فاز جدا هستند. نمونه بالا کانفیگ کامل پراکسی نیست. هر پراکسی به هر دو IP دسترسی داشته باشد. برای TLS پراکسی/Agent از PSK یا certificate و template/host Encryption منطبق استفاده کنید؛ کلید واقعی در ریپو نباشد.

## Agent Passive

هاست مستقیم: Server شامل IP B و C با **comma**. هاست پشت پراکسی: Server شامل IP پراکسی مسئول و در سناریوی proxy group، همه اعضای مجاز گروه باشد. Agent2، ServerActive خالی و templateهای Passive.

```ini
Server=REPLACE_B_IP,REPLACE_C_IP
Hostname=REPLACE_EXACT_HOSTNAME
```

برای هاست پشت پراکسی، B/C را با IP پراکسی‌های مجاز عوض کنید. در UI فیلد Monitored by متناسب با Server/Proxy/Proxy group تعیین شود. SNMPv3 authPriv ترجیح دارد؛ secretها را در macroهای secret و vault سازمانی نگه دارید. در URL checks بررسی TLS certificate/hostname را فعال کنید.
