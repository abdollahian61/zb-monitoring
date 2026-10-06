"""Three static review passes; never connects to or changes production nodes."""
import json
import re
import subprocess
from pathlib import Path

ROOT = Path(__file__).resolve().parents[1]
INVENTORY = json.loads((ROOT / 'configs/inventory.json').read_text())

def config(name):
    lines = (ROOT / 'configs' / name).read_text().splitlines()
    pairs = [line.split('=', 1) for line in lines if '=' in line and not line.startswith('#')]
    keys = [key.strip() for key, _ in pairs]
    assert len(keys) == len(set(keys)), f'Duplicate key in {name}'
    return {key.strip(): value.strip() for key, value in pairs}

def identity():
    for filename, role in [('zabbix-server-b.conf', 'primary'), ('zabbix-server-c.conf', 'standby')]:
        conf = config(filename)
        node = INVENTORY['nodes'][role]
        assert conf['HANodeName'] == node['hostname']
        assert conf['NodeAddress'] == node['ip'] + ':10051'
        assert conf['DBHost'] == INVENTORY['nodes']['database']['ip']
        assert conf['DBPassword'] == 'REPLACE_DB_PASSWORD'
    for role in ['proxy01', 'proxy02']:
        conf = config(f'zabbix-proxy-{role}.conf')
        assert conf['Hostname'] == INVENTORY['nodes'][role]['hostname']
        assert conf['Server'] == '192.168.42.2:10051;192.168.42.3:10051'
        assert conf['ProxyMode'] == '0'
    assert config('mariadb.cnf')['bind-address'] == '192.168.42.4'
    text = '\n'.join(f.read_text() for f in [ROOT/'README.md', *ROOT.glob('docs/*.md'), *ROOT.glob('configs/*.conf')])
    for old in ['REPLACE_DB_IP', 'REPLACE_B_IP', 'REPLACE_C_IP', 'eit-zbx-srv01', 'eit-zbx-srv02']:
        assert old not in text, old

def syntax():
    count = 0
    for f in ROOT.glob('docs/*.md'):
        text = f.read_text()
        assert text.count('```') % 2 == 0, f
        for block in re.findall(r'```bash\n(.*?)```', text, re.S):
            check = subprocess.run(['bash', '-n'], input=block, text=True, capture_output=True)
            assert check.returncode == 0, (f, check.stderr)
            count += 1
        for target in re.findall(r'\]\(([^)]+)\)', text):
            if not target.startswith('http'):
                assert (f.parent / target).exists(), (f, target)
    subprocess.run(['git', 'diff', '--check'], cwd=ROOT, check=True)
    return count

def topology():
    cfg = (ROOT/'configs/haproxy.cfg').read_text()
    assert '192.168.42.2:8080' in cfg and '192.168.42.3:8080' in cfg
    assert INVENTORY['frontend_fqdn'] in cfg
    hosts = (ROOT/'configs/hosts.example').read_text()
    for node in INVENTORY['nodes'].values():
        assert f"{node['ip']} {node['hostname']}" in hosts
    db = (ROOT/'docs/01-node-a-database.md').read_text()
    for ip in ['192.168.42.2', '192.168.42.3']:
        assert f"'zabbix'@'{ip}'" in db
    assert "'zabbix'@'%'" not in db
    assert 'innodb_flush_method' not in config('mariadb.cnf')
    assert config('mariadb.cnf')['innodb_flush_log_at_trx_commit'] == '1'

for round_number in range(1, 4):
    identity()
    blocks = syntax()
    topology()
    print(f'Pass {round_number}/3: identity, {blocks} Bash blocks, links, config keys, topology PASS')
print('Static checks only: VM installation, package resolution and failover require live testing.')
