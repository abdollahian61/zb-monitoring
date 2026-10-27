# پراکسی ابرآمد و نتیجه‌های اجرا — 2026-10-27

## وضعیت تأییدشده
- نصب از JFrog با Remote واقعی `artifactory/zabbix` موفق شد. `eit-zabbix-7.4` آدرس اشتباه بود.
- نسخه کامل بسته‌ها `1:7.4.15-1+ubuntu24.04` است.
- import سرور پس از رفع خطای trigger/binlog با پیام IMPORT OK تمام شد؛ 207 جدول و dbversion برابر 7040000 / 7040011 گزارش شد. import تکرار نشود.
- HA ابتدا Pri=standby و HA=active بود. کاربر پس از توقف HA، فعال‌شدن Pri را تأیید کرد. بازگشت نود دوم به standby در خروجی نهایی ثبت نشده است.
- وب روی 8080 است؛ پاسخ سایت پیش‌فرض روی 80 معیار سلامت زبیکس نیست. نبود zabbix.conf.php و هدایت به setup.php نشان‌دهنده تکمیل‌نشدن frontend است.
- خطای proxy not found برای Proxy02 مشاهده شد؛ راه رفع، ثبت Active proxy با نام دقیق کانفیگ است. نتیجه نهایی رفع آن هنوز گزارش نشده است.
- کاربر افزودن پراکسی ابرآمد و اتصال به همان دو master را تأیید کرده است. IP، منابع و نام نهایی ابرآمد اعلام نشده؛ EIT-ZBX-Proxy-Abramad فقط نام پیش‌فرض پیشنهادی است. نصب و ارتباط آن هنوز تأیید نشده است.

## نصب ابرآمد
روی Ubuntu 24.04 amd64 با root، از checkout همین مخزن:
```bash
bash scripts/install-zabbix-proxy-abramad.sh
```

اسکریپت مخزن قدیمی را اصلاح و مخزن صحیح را در صورت نبود اضافه می‌کند. بسته‌های 7.4.15 نصب، کانفیگ قبلی بکاپ و پراکسی Active با SQLite آماده می‌شود. از ProxyConfigFrequency به‌جای ConfigFrequency منسوخ استفاده می‌شود. Agent2 نصب می‌شود اما خودمانیتورینگ آن مرحله جداست. داده SQLite موجود حذف نمی‌شود.

در پنل Data collection → Proxies → Create proxy:
- Proxy name دقیقاً نام واردشده هنگام نصب.
- Proxy mode: Active؛ فعلاً بدون Proxy group.
- برای baseline اسکریپت Connections from proxy: No encryption. PSK ایجنت به‌صورت خودکار ارتباط proxy-server را رمزگذاری نمی‌کند.
- آدرس مجاز اتصال، در صورت تنظیم، IP واقعی خروجی پراکسی پس از NAT باشد.

سپس روی ابرآمد:
```bash
systemctl enable --now zabbix-proxy
systemctl status zabbix-proxy --no-pager -l
tail -n 50 /var/log/zabbix/zabbix_proxy.log
```

مسیر ابرآمد به هر دو master روی TCP 10051 لازم است. برای دریافت داده، از ابرآمد به Agentها TCP 10050، تجهیزات SNMP روی UDP 161 و URLها روی پورت سرویس دسترسی لازم است. بسته‌بودن 10051 روی standby به‌تنهایی خطای HA نیست؛ وضعیت را روی Active با ha_status بررسی کنید.

## Agentهای ابرآمد
```bash
bash scripts/install-zabbix-agent.sh
```
گزینه 3 را انتخاب و IP یا DNS واقعی collector ابرآمد را وارد کنید. هیچ IP فرضی برای ابرآمد ثبت نشده است. در پنل Monitored by را روی همین پراکسی و template را روی Linux by Zabbix agent بگذارید. DNS باید روی خود Agent به IP واقعی مبدأ اتصال resolve شود؛ در صورت NAT، IP مشاهده‌شده در لاگ Agent ملاک است.

## PSK برای Agent Passive
Identity اعلام‌شده کاربر: `PSK-001`. کلید واقعی در مخزن ذخیره نشده است. روی Linux کلید را بدون echo و بدون قرارگرفتن در history دریافت کنید:
```bash
read -rsp 'PSK hex: ' ZBX_PSK
echo
if [[ "$ZBX_PSK" =~ ^[[:xdigit:]]{32,512}$ && $(( ${#ZBX_PSK} % 2 )) -eq 0 ]]; then
    install -o root -g zabbix -m 640 /dev/null /etc/zabbix/agent.psk
    printf '%s\n' "$ZBX_PSK" > /etc/zabbix/agent.psk
else
    echo 'Invalid PSK'; unset ZBX_PSK; exit 1
fi
unset ZBX_PSK
```

در کانفیگ Agent خطوط فعال تکراری نسازید:
```ini
TLSAccept=psk
TLSPSKIdentity=PSK-001
TLSPSKFile=/etc/zabbix/agent.psk
```
ServerActive غیرفعال بماند. TLSAccept برای اتصال ورودی Passive است. در Host → Encryption، Connections to host را PSK و identity و secret را دقیقاً مطابق Agent قرار دهید. سپس:
```bash
zabbix_agent2 -T -c /etc/zabbix/zabbix_agent2.conf &&
systemctl restart zabbix-agent2
```

در Windows فایل PSK را بدون BOM بسازید، دسترسی خواندن را به حساب سرویس و مدیران محدود کنید و TLSPSKFile را به مسیر ویندوزی آن بدهید. خطای connection rejected / allowed hosts مربوط به Server و DNS/NAT است؛ افزودن PSK آن را رفع نمی‌کند.

منبع پارامتر پراکسی: https://www.zabbix.com/documentation/7.4/en/manual/distributed_monitoring/proxies/sync
