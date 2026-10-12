# نصب Agent2 Passive

اسکریپت [install-zabbix-agent.sh](../scripts/install-zabbix-agent.sh) برای Ubuntu 24.04 amd64 است. فایل را از این مخزن روی سرور مقصد قرار دهید و با root اجرا کنید:

```bash
chmod 700 install-zabbix-agent.sh
bash install-zabbix-agent.sh
```

اسکریپت آدرس قدیمی eit-zabbix-7.4 را با بکاپ اصلاح می‌کند، وجود مخزن فعال noble/main را بررسی می‌کند، در صورت نیاز مخزن داخلی را اضافه و نسخه کامل 1:7.4.15-1+ubuntu24.04 را نصب می‌کند. Python3 باید نصب باشد. مخزن با Trusted: yes مطابق انتخاب کاربر تنظیم می‌شود.

Hostname را دقیقاً مطابق Host name پنل وارد کنید. گزینه 1 برای Pri/HA و گزینه 2 برای مجازکردن هر دو پراکسی است. ServerActive غیرفعال و TCP 10050 فعال می‌شود. کانفیگ اصلی و includeها بکاپ دارند و قبل از restart اعتبارسنجی می‌شوند. تنظیمات TLS موجود حفظ می‌شوند؛ Encryption پنل باید با آنها مطابقت داشته باشد.

در پنل Data collection → Hosts، template برابر Linux by Zabbix agent، Agent interface برابر IP هاست و پورت 10050 و Monitored by برابر Server یا پراکسی مسئول باشد. مجازکردن دو IP به‌تنهایی HA پراکسی ایجاد نمی‌کند. فایروال تغییر نمی‌کند؛ مسیر collector به هاست روی TCP 10050 را باز کنید.
