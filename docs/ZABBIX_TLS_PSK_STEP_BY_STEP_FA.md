<div dir="rtl" align="right">

# Zabbix 7.4 TLS-PSK: راهنمای گام‌به‌گام برای Windows Agent2، Linux Agent2، Proxy و Server

> **هدف:** امن‌سازی ارتباط Zabbix Agent2 ↔ Proxy و Proxy ↔ Zabbix Server با TLS-PSK. مناسب معماری دو سرور HA، دو Proxy و Agentهای عمدتاً Passive. دستورها را ابتدا روی **یک هاست آزمایشی** اجرا کنید. هیچ PSK واقعی را در Git ذخیره نکنید.

## 0. نقشه ارتباط و اصطلاحات

## نمودار ارتباط

</div>


```text
Windows Agent2 (Passive) <-- TCP/10050 TLS-PSK --> Proxy01
Linux Agent2   (Passive) <-- TCP/10050 TLS-PSK --> Proxy02
Proxy01 (Active) --> TCP/10051 TLS-PSK --> Zabbix Server HA
Proxy02 (Active) --> TCP/10051 TLS-PSK --> Zabbix Server HA
```

<div dir="rtl" align="right">


- **PSK** یک کلید محرمانه مشترک است؛ **جفت Public/Private Key نیست**. Identity نام شناسایی کلید است و محرمانه نیست؛ مقدار PSK محرمانه است.
- **Passive Agent**: پراکسی به Agent روی TCP/10050 وصل می‌شود؛ در Agent از `TLSAccept=psk` استفاده می‌کنیم. `TLSConnect` برای اتصال خروجی Agent (Active checks) است.
- **Active Proxy**: پراکسی به سرور روی TCP/10051 وصل می‌شود؛ در Proxy از `TLSConnect=psk` استفاده می‌کنیم.
- PSK بین Agent و Proxy در **Frontend → Host → Encryption** ثبت می‌شود و به Proxy مسئول آن Host توزیع می‌شود. **PSK مربوط به Agent را در فایل کانفیگ Proxy کپی نکنید.**
- PSK بین Proxy و Server **جدا** است: در فایل Proxy و در **Frontend → Proxy → Encryption** تنظیم می‌شود.
- در HA، تنظیمات Host و Proxy در دیتابیس مشترک قرار دارد. PSK واقعی را در این ریپو یا اسکرین‌شات عمومی قرار ندهید.

## 1. پیش‌نیازها و چک‌لیست قبل از تغییر

1. در Frontend نسخه و Proxy مسئول Host را یادداشت کنید: **Data collection → Hosts → [host]**؛ مقدار **Monitored by proxy** را بررسی کنید.
2. مطمئن شوید آیتم آزمایشی **Type = Zabbix agent** است، نه `Zabbix agent (active)`.
3. مسیر و نام سرویس Agent2 و Proxy را ثبت و از فایل‌های کانفیگ بکاپ بگیرید.
4. دسترسی شبکه: **Proxy → Agent: TCP 10050** و **Active Proxy → Zabbix Server HA nodes: TCP 10051**. فایروال باید این جهت‌ها را مجاز بداند.
5. ساعت‌ها همگام و نسخه Agent2/Proxy دارای پشتیبانی TLS باشند. فایل‌های PSK باید تنها برای حساب سرویس و مدیر سیستم خواندنی باشند.
6. از هر Host یک PSK مستقل توصیه می‌شود. اگر یک PSK را برای چند Host استفاده می‌کنید، **Identity یکسان باید به مقدار PSK یکسان اشاره کند**.
7. در زمان مهاجرت ممکن است مانیتورینگ برای چند دقیقه قطع شود؛ تغییر Agent و Frontend را هماهنگ انجام دهید.

## 2. Linux Agent2: تولید کلید و تنظیمات

**روی همان Linux Host** (نه روی Proxy):

</div>


```bash
# ساخت کلید تصادفی 256 بیتی در فایل محرمانه
sudo install -d -m 0755 /etc/zabbix
openssl rand -hex 32 | sudo tee /etc/zabbix/agent2.psk >/dev/null
sudo chown zabbix:zabbix /etc/zabbix/agent2.psk
sudo chmod 0600 /etc/zabbix/agent2.psk
sudo cp -a /etc/zabbix/zabbix_agent2.conf /etc/zabbix/zabbix_agent2.conf.bak
```

<div dir="rtl" align="right">


در `/etc/zabbix/zabbix_agent2.conf` پارامترهای موجود را **ویرایش کنید، نه اینکه چند تعریف تکراری اضافه کنید**:

</div>


```ini
Server=PROXY01_IP,PROXY02_IP
ListenPort=10050
TLSAccept=psk
TLSPSKIdentity=EIT-LINUX-001
TLSPSKFile=/etc/zabbix/agent2.psk
```

<div dir="rtl" align="right">


**نکته:** `Server` فهرست IP/DNS مجاز برای Passive connections است. اگر فقط Proxy01 این Host را مانیتور می‌کند، می‌توانید فقط IP همان Proxy را قرار دهید. برای Failover، هر پراکسی‌ای که واقعاً قرار است متصل شود باید مجاز باشد. `ServerActive` برای Passive-only ضروری نیست. `StartAgents` را برای Agent2 تنظیم نکنید.

هنوز Restart نکنید؛ ابتدا مرحله 4 (Frontend) را آماده کنید. برای دیدن مقدار PSK به‌صورت امن روی همان ماشین از `sudo cat /etc/zabbix/agent2.psk` استفاده کنید و آن را در تیکت، چت یا مخزن ذخیره نکنید.

## 3. Windows Agent2: تولید کلید و تنظیمات

PowerShell را با **Run as Administrator** باز کنید. مسیر نصب را با محیط خودتان تطبیق دهید:

</div>


```powershell
$dir = 'C:\Program Files\Zabbix Agent 2'
$pskPath = Join-Path $dir 'agent2.psk'
$bytes = New-Object byte[] 32
$rng = [System.Security.Cryptography.RandomNumberGenerator]::Create()
try { $rng.GetBytes($bytes) } finally { $rng.Dispose() }
$hex = [BitConverter]::ToString($bytes).Replace('-','').ToLowerInvariant()
[System.IO.File]::WriteAllText($pskPath, $hex + "`n", [System.Text.Encoding]::ASCII)
# بررسی دسترسی و محدودسازی ACL متناسب با حساب اجرای سرویس:
Get-CimInstance Win32_Service -Filter "Name='Zabbix Agent 2'" | Select-Object Name,StartName,PathName
icacls $pskPath
```

<div dir="rtl" align="right">


**مهم:** ACL فایل PSK را طوری تنظیم کنید که فقط Administrators، SYSTEM و حساب واقعی سرویس Zabbix Agent2 امکان خواندن داشته باشند. پیش از تغییر ACL، خروجی `StartName` را ببینید؛ حذف مجوز حساب سرویس باعث خطای TLS می‌شود. مسیر فایل ممکن است بسته به نصب متفاوت باشد.

از فایل `zabbix_agent2.conf` بکاپ بگیرید و تنظیمات موجود را اصلاح کنید:

</div>


```ini
Server=PROXY01_IP,PROXY02_IP
ListenPort=10050
TLSAccept=psk
TLSPSKIdentity=EIT-WIN-001
TLSPSKFile=C:\Program Files\Zabbix Agent 2\agent2.psk
```

<div dir="rtl" align="right">


برای پیدا کردن مسیر واقعی کانفیگ از `PathName` سرویس در خروجی دستور بالا استفاده کنید؛ فرض نکنید همیشه در یک مسیر است. مقدار PSK، **محتوای فایل** است نه اسم فایل.

## 4. Frontend: تعریف کلید Agent برای Host

1. وارد **Data collection → Hosts** شوید.
2. Host آزمایشی را باز کنید؛ در تب Host بررسی کنید **Monitored by proxy** پراکسی درست باشد.
3. تب **Encryption** را باز کنید.
4. در **Connections to host** گزینه **PSK** را انتخاب کنید؛ چون Proxy به Agent Passive متصل می‌شود.
5. در **PSK identity** مقدار دقیق `TLSPSKIdentity` همان Agent را وارد کنید.
6. در **PSK** مقدار 64 کاراکتر hex فایل PSK را وارد کنید، **نه مسیر فایل و نه کلید عمومی**.
7. برای Agentهای Passive-only، تنظیم **Connections from host** برای Active checks لازم نیست تغییر کند؛ اگر Active checks هم دارید، گزینه PSK را در آن بخش نیز متناسب با `TLSConnect` تنظیم کنید.
8. **Update** را بزنید. صبر کنید Proxy پیکربندی جدید را دریافت کند (در Active Proxy این همگام‌سازی دوره‌ای است).

**سپس** Agent را Restart کنید:

</div>


```bash
sudo systemctl restart zabbix-agent2
sudo systemctl status zabbix-agent2 --no-pager
sudo journalctl -u zabbix-agent2 -n 50 --no-pager
```

<div dir="rtl" align="right">


</div>


```powershell
Restart-Service 'Zabbix Agent 2'
Get-Service 'Zabbix Agent 2'
```

<div dir="rtl" align="right">


در **Monitoring → Latest data** مقدار تازه برای یک Item از نوع Passive را چک کنید. فقط سبز بودن Availability کافی نیست؛ **timestamp جدید** را بررسی کنید.

## 5. امن‌سازی ارتباط Active Proxy → Zabbix Server

این مرحله **مستقل** از PSKهای Agentها است و روی **هر Proxy جداگانه** انجام می‌شود.

روی Proxy01:

</div>


```bash
openssl rand -hex 32 | sudo tee /etc/zabbix/proxy.psk >/dev/null
sudo chown zabbix:zabbix /etc/zabbix/proxy.psk
sudo chmod 0600 /etc/zabbix/proxy.psk
sudo cp -a /etc/zabbix/zabbix_proxy.conf /etc/zabbix/zabbix_proxy.conf.bak
```

<div dir="rtl" align="right">


در `/etc/zabbix/zabbix_proxy.conf`:

</div>


```ini
# سایر تنظیمات Server و Hostname موجود را حفظ کنید
TLSConnect=psk
TLSPSKIdentity=EIT-ZBX-PROXY01
TLSPSKFile=/etc/zabbix/proxy.psk
```

<div dir="rtl" align="right">


در Frontend: **Administration → Proxies** (در برخی چیدمان‌های 7.4 مسیر **Data collection → Proxies** است)، Proxy01 را باز کنید و در **Encryption**، اتصال **PSK** را انتخاب کنید؛ Identity را `EIT-ZBX-PROXY01` و PSK را **محتوای فایل Proxy01** قرار دهید. ذخیره کنید.

سپس:

</div>


```bash
sudo systemctl restart zabbix-proxy
sudo systemctl status zabbix-proxy --no-pager
sudo journalctl -u zabbix-proxy -n 100 --no-pager
```

<div dir="rtl" align="right">


برای Proxy02 **یک کلید جدید** بسازید و Identity را `EIT-ZBX-PROXY02` قرار دهید. مقدار PSK آن را در رکورد **همان Proxy02** در Frontend ثبت کنید.

**توجه HA:** هر دو Zabbix Server باید به دیتابیس مشترک دسترسی داشته باشند و Proxy باید برای اتصال به نود فعال مطابق معماری HA پیکربندی شده باشد. PSKهای Proxy در دیتابیس Zabbix نگهداری می‌شوند؛ نیازی به کپی کردن `proxy.psk` روی دو Server نیست. این تنظیم، TLS ارتباط **Proxy→Server** را امن می‌کند؛ نه ارتباط Frontend مرورگر یا MariaDB.

## 6. تست دقیق و عیب‌یابی

</div>

<div dir="rtl" align="right">


| علامت | بررسی |
|---|---|
| Latest data به‌روز نمی‌شود | Proxy صحیح، Type آیتم Passive، مسیر TCP/10050، لاگ Agent/Proxy |
| TLS handshake failed / PSK identity not found | یکسان بودن Identity و محتوای PSK در Agent و Host |
| Connection refused / timeout | سرویس Agent2، فایروال، IP داخل `Server`، مسیر شبکه |
| Cannot read PSK file | ACL ویندوز یا مالکیت و chmod لینوکس |
| Proxy به Server متصل نمی‌شود | TLSConnect، Identity/PSK در رکورد Proxy، TCP/10051، HA endpoint |
| بعد از تغییر Frontend هنوز خطا هست | زمان Sync تنظیمات Proxy، لاگ Proxy و داده تازه Latest data |



تست اتصال TCP از Proxy به Agent:

</div>


```bash
nc -vz AGENT_IP 10050
```

<div dir="rtl" align="right">


این تست **فقط TCP را تأیید می‌کند، نه TLS-PSK**. برای تست واقعی، آخرین مقدار Item و لاگ‌های هر دو سمت را بررسی کنید. اجرای `zabbix_get` بدون گزینه‌های TLS روی Agent با `TLSAccept=psk` معمولاً جواب نمی‌دهد.

## 7. Rollback در صورت اختلال

1. فایل‌های بکاپ Agent/Proxy را حفظ کنید.
2. برای برگشت Agent، تنظیمات Encryption Host را با کانفیگ قبلی هماهنگ کنید؛ سپس فایل Agent را از بکاپ بازگردانید و سرویس را Restart کنید.
3. برای برگشت Proxy، Encryption همان Proxy را با کانفیگ قبلی هماهنگ کنید؛ فایل Proxy را بازگردانید و سرویس را Restart کنید.
4. هرگز تنها یک سمت را به حالت بدون TLS برنگردانید؛ عدم تطابق، ارتباط را قطع می‌کند.
5. بعد از Rollback دریافت مقدار جدید در Latest data و وضعیت اتصال Proxy را تأیید کنید.

## 8. چک‌لیست پایان کار

- [ ] PSK اختصاصی 32-byte برای Agent آزمایشی ساخته شد
- [ ] فایل PSK فقط برای حساب سرویس و مدیر قابل خواندن است
- [ ] Agent2: `TLSAccept=psk`، Identity و File درست
- [ ] Frontend Host: Connections to host = PSK و Identity/PSK مطابق
- [ ] Proxy تنظیمات Host را Sync کرده
- [ ] Latest data پس از تغییر Timestamp جدید دارد
- [ ] Proxy01: PSK مستقل، TLSConnect و Encryption Frontend درست
- [ ] Proxy02: PSK مستقل، TLSConnect و Encryption Frontend درست
- [ ] هر دو Proxy به Zabbix HA متصل هستند
- [ ] Rollback و محل نگهداری امن کلیدها ثبت شده‌اند

## 9. راهنمای متنی پنل Zabbix

</div>


```text
Data collection > Hosts > [HOST] > Encryption
  Connections to host: [PSK]
  PSK identity:        [EIT-WIN-001]
  PSK:                 [64 hex characters - secret]
  [Update]

Proxy (Active) > Server : TCP/10051, TLSConnect=psk
Proxy > Agent (Passive): TCP/10050, Agent TLSAccept=psk
```

<div dir="rtl" align="right">


**این راهنما عمداً بدون اسکرین‌شات تهیه شده است.**

## منابع رسمی

- [Zabbix 7.4: Encryption using PSK](https://www.zabbix.com/documentation/7.4/en/manual/encryption/using_pre_shared_keys)
- [Zabbix 7.4: Agent2 configuration](https://www.zabbix.com/documentation/7.4/en/manual/appendix/config/zabbix_agent2)
- [Zabbix 7.4: Proxy configuration](https://www.zabbix.com/documentation/7.4/en/manual/appendix/config/zabbix_proxy)

</div>
