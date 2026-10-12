#!/usr/bin/env bash
set -euo pipefail
[[ $EUID -eq 0 ]] || { echo 'Run as root'; exit 1; }
. /etc/os-release
[[ "$ID" == ubuntu && "$VERSION_ID" == 24.04 ]] || { echo 'Ubuntu 24.04 required'; exit 1; }
[[ $(dpkg --print-architecture) == amd64 ]] || { echo 'amd64 required'; exit 1; }
command -v python3 >/dev/null || { echo 'Install python3 first'; exit 1; }
read -rp "Zabbix hostname [$(hostname)]: " ZBX_HOSTNAME
ZBX_HOSTNAME=${ZBX_HOSTNAME:-$(hostname)}
[[ "$ZBX_HOSTNAME" =~ ^[a-zA-Z0-9._-]+$ ]] || { echo 'Invalid hostname'; exit 1; }
echo '1) Direct: Pri + HA'
echo '2) Through Proxy01 + Proxy02'
read -rp 'Select [1/2]: ' MODE
case "$MODE" in
  1) COLLECTORS='192.168.42.2,192.168.42.3' ;;
  2) COLLECTORS='192.168.42.5,192.168.42.6' ;;
  *) echo 'Invalid selection'; exit 1 ;;
esac
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
apt-get install -y zabbix-agent2='1:7.4.15-1+ubuntu24.04'
BACKUP=$(mktemp -d /root/zabbix-agent-backup.XXXXXX)
cp -a /etc/zabbix "$BACKUP/"
python3 - "$COLLECTORS" "$ZBX_HOSTNAME" "$BACKUP" <<'PY'
import glob, re, shutil, sys
from pathlib import Path
seen = set()
keys = {'Server','ServerActive','Hostname','HostnameItem','ListenIP','ListenPort'}
def clean(path):
    path = Path(path).resolve()
    if path in seen: return
    seen.add(path)
    # Preserve included files even when outside /etc/zabbix.
    backup = Path(sys.argv[3]) / 'included' / str(path).lstrip('/')
    backup.parent.mkdir(parents=True, exist_ok=True)
    shutil.copy2(path, backup)
    result = []
    for line in path.read_text().splitlines():
        m = re.match(r'^\s*([A-Za-z0-9]+)\s*=(.*)$', line)
        if m and m[1] == 'Include':
            pattern = m[2].strip()
            if not Path(pattern).is_absolute(): pattern = str(path.parent / pattern)
            for child in glob.glob(pattern):
                if Path(child).is_file(): clean(child)
        if m and m[1] in keys: line = '# Disabled by passive installer: ' + line
        result.append(line)
    path.write_text('\n'.join(result) + '\n')
main = Path('/etc/zabbix/zabbix_agent2.conf')
clean(main)
with main.open('a') as f:
    f.write(f'\n# EIT Passive\nServer={sys.argv[1]}\nHostname={sys.argv[2]}\nListenIP=0.0.0.0\nListenPort=10050\n')
PY
if ! zabbix_agent2 -T -c /etc/zabbix/zabbix_agent2.conf; then
    cp -a "$BACKUP/included/." /
    echo "Validation failed; configuration restored from $BACKUP"
    exit 1
fi
systemctl enable zabbix-agent2
systemctl restart zabbix-agent2
systemctl is-active --quiet zabbix-agent2 || { journalctl -u zabbix-agent2 -n 30 --no-pager; exit 1; }
printf '\nHostname: %s\nMode: Passive\nCollectors: %s\nBackup: %s\n' "$ZBX_HOSTNAME" "$COLLECTORS" "$BACKUP"
ss -lntp | grep ':10050'
