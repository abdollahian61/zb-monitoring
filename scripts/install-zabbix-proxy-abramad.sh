#!/usr/bin/env bash
set -euo pipefail
[[ $EUID -eq 0 ]] || { echo 'Run as root'; exit 1; }
. /etc/os-release
[[ "$ID" == ubuntu && "$VERSION_ID" == 24.04 && $(dpkg --print-architecture) == amd64 ]] || { echo 'Ubuntu 24.04 amd64 required'; exit 1; }
command -v python3 >/dev/null || { echo 'Install python3 first'; exit 1; }
read -rp 'Proxy name [EIT-ZBX-Proxy-Abramad]: ' PROXY_NAME
PROXY_NAME=${PROXY_NAME:-EIT-ZBX-Proxy-Abramad}
[[ "$PROXY_NAME" =~ ^[a-zA-Z0-9._-]+$ ]] || { echo 'Invalid name'; exit 1; }
python3 <<'PY'
import re, shutil, tempfile
from datetime import datetime
from pathlib import Path
url = 'https://repository.iraneit.dev/artifactory/zabbix'
old = 'https://repository.iraneit.dev/artifactory/eit-zabbix-7.4'
folder = Path('/etc/apt/sources.list.d')
folder.mkdir(parents=True, exist_ok=True)
files = [Path('/etc/apt/sources.list'), *folder.glob('*.list'), *folder.glob('*.sources')]
found = False
for path in files:
    if not path.is_file(): continue
    text = path.read_text()
    repaired = re.sub(re.escape(old) + r'(?=/|\s|$)', url, text)
    if repaired != text:
        shutil.copy2(path, str(path) + '.bak.' + datetime.now().strftime('%Y%m%d-%H%M%S-%f'))
        path.write_text(repaired)
        text = repaired
        print('Repaired:', path)
    if path.suffix == '.sources':
        for block in re.split(r'\n\s*\n', text):
            fields = {}; key = None
            for line in block.splitlines():
                if not line.strip() or line.lstrip().startswith('#'): continue
                if line[0].isspace() and key: fields[key] += ' ' + line.strip()
                elif ':' in line:
                    key, value = line.split(':', 1)
                    key = key.strip().lower(); fields[key] = value.strip()
            if fields.get('enabled', 'yes').lower() == 'no': continue
            found |= ('deb' in fields.get('types','').split() and 'noble' in fields.get('suites','').split() and 'main' in fields.get('components','').split() and url in [u.rstrip('/') for u in fields.get('uris','').split()])
    else:
        for line in text.splitlines():
            m = re.match(r'^deb\s+(?:\[[^\]]*\]\s+)?(\S+)\s+(\S+)\s+(.+)$', line.split('#',1)[0].strip())
            if m and m[1].rstrip('/') == url and m[2] == 'noble' and 'main' in m[3].split(): found = True
if not found:
    path = folder / 'eit-zabbix.sources'
    if path.exists():
        fd, name = tempfile.mkstemp(prefix='eit-zabbix-agent-', suffix='.sources', dir=folder)
        import os
        os.close(fd); path = Path(name)
    path.write_text(f'Types: deb\nURIs: {url}\nSuites: noble\nComponents: main\nArchitectures: amd64 all\nTrusted: yes\n')
    path.chmod(0o644)
    print('Added:', path)
else: print('Repository already configured')
PY

apt-get update
apt-get install -y zabbix-proxy-sqlite3='1:7.4.15-1+ubuntu24.04' zabbix-agent2='1:7.4.15-1+ubuntu24.04' zabbix-get='1:7.4.15-1+ubuntu24.04' fping sqlite3
# Refuse to overwrite an already-used proxy database/configuration.
if [[ -s /var/lib/zabbix/zabbix_proxy.db ]]; then
    echo 'Existing proxy database found; inspect configuration before changing identity.'
    exit 1
fi
systemctl stop zabbix-proxy
cp -a /etc/zabbix/zabbix_proxy.conf "/etc/zabbix/zabbix_proxy.conf.bak.$(date +%Y%m%d-%H%M%S)"
install -d -o zabbix -g zabbix -m 750 /var/lib/zabbix
install -d -o zabbix -g zabbix -m 755 /var/log/zabbix
cat > /etc/zabbix/zabbix_proxy.conf <<EOF
ProxyMode=0
Server=192.168.42.2:10051;192.168.42.3:10051
Hostname=$PROXY_NAME
LogFile=/var/log/zabbix/zabbix_proxy.log
LogFileSize=20
PidFile=/run/zabbix/zabbix_proxy.pid
SocketDir=/run/zabbix
DBName=/var/lib/zabbix/zabbix_proxy.db
ProxyOfflineBuffer=24
ProxyConfigFrequency=60
DataSenderFrequency=1
CacheSize=64M
HistoryCacheSize=32M
Timeout=10
FpingLocation=$(command -v fping)
EOF
chown root:zabbix /etc/zabbix/zabbix_proxy.conf
chmod 640 /etc/zabbix/zabbix_proxy.conf
echo "Configured Active proxy: $PROXY_NAME"
echo 'Register it in Data collection > Proxies, then run: systemctl enable --now zabbix-proxy'
echo 'Agent2 self-monitoring must be configured separately.'
