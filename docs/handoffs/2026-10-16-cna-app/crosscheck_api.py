#!/usr/bin/env python3
"""Cruza o lote CNA com a API de produção do legal_data (somente GET)."""
import json, os, sys, re, time, urllib.request, urllib.error, unicodedata, collections

BATCH = sys.argv[1]
OUT = sys.argv[2]

env = {}
for line in open(os.path.expanduser('~/code/env')):
    line = line.strip()
    if '=' in line and not line.startswith('#'):
        k, v = line.split('=', 1)
        env[k] = v
KEY = env['LEGAL_DATA_API_KEY']
BASE = 'https://' + env['LEGAL_DATA_ENDPOINT'].rstrip('/')


def get(path):
    req = urllib.request.Request(BASE + path, headers={'X-API-KEY': KEY, 'Accept': 'application/json'})
    try:
        with urllib.request.urlopen(req, timeout=30) as r:
            return r.status, json.loads(r.read().decode())
    except urllib.error.HTTPError as e:
        body = e.read().decode(errors='replace')
        try:
            body = json.loads(body)
        except Exception:
            pass
        return e.code, body


def norm(s):
    s = unicodedata.normalize('NFKD', s or '').encode('ascii', 'ignore').decode().upper()
    return re.sub(r'\s+', ' ', re.sub(r'[^A-Z\s]', ' ', s)).strip()


rows = [json.loads(l) for l in open(os.path.join(BATCH, 'legal_data.jsonl')) if l.strip()]
print('registros no lote:', len(rows), file=sys.stderr)

report = {'lawyers': [], 'societies': {}, 'summary': collections.Counter()}
soc_seen = {}

for i, r in enumerate(rows):
    oab = f"{r['state']}_{r['oab_number']}"
    st, body = get(f'/lawyer/{oab}')
    entry = {'oab_id': oab, 'name': r['full_name'], 'tipo': r.get('tipo_inscricao'), 'situation_batch': r.get('situation'), 'http': st}
    if st == 200 and isinstance(body, dict) and 'principal' in body:
        p = body['principal']
        supps = body.get('supplementaries') or []
        # o registro consultado pode ser o principal ou uma das suplementares
        me = p if p.get('oab_id', '').upper() == oab.upper() else next((s for s in supps if s.get('oab_id', '').upper() == oab.upper()), p)
        entry['exists'] = True
        entry['db'] = {k: me.get(k) for k in ('full_name', 'situation', 'city', 'address', 'phone_number_1', 'phone_number_2', 'suplementary', 'cna_picture', 'has_society')}
        entry['principal_oab'] = p.get('oab_id')
        entry['cluster_size'] = 1 + len(supps)
        entry['db_societies'] = [(s.get('inscricao'), s.get('state'), s.get('name')) for s in (me.get('societies') or [])]
        diffs = {}
        if norm(me.get('full_name')) != norm(r['full_name']):
            diffs['full_name'] = (me.get('full_name'), r['full_name'])
        if (me.get('situation') or '').upper() != (r.get('situation') or '').upper():
            diffs['situation'] = (me.get('situation'), r.get('situation'))
        if norm(me.get('city')) != norm(r.get('city')) and r.get('city'):
            diffs['city'] = (me.get('city'), r.get('city'))
        entry['diffs'] = diffs
        report['summary']['exists'] += 1
        report['summary']['exists_with_diffs'] += bool(diffs)
        if r.get('tipo_inscricao') == 'SUPLEMENTAR':
            report['summary']['supl_exists'] += 1
            if p.get('oab_id', '').upper() != oab.upper():
                report['summary']['supl_linked'] += 1
            else:
                report['summary']['supl_unlinked'] += 1
    elif st == 404:
        entry['exists'] = False
        report['summary']['new'] += 1
        if r.get('tipo_inscricao') == 'SUPLEMENTAR':
            report['summary']['supl_new'] += 1
    else:
        entry['exists'] = None
        entry['error'] = body if isinstance(body, str) else json.dumps(body)[:300]
        report['summary']['error'] += 1
    report['lawyers'].append(entry)

    for s in r.get('societies') or []:
        k = f"{s.get('state')}_{s.get('inscricao')}"
        soc_seen.setdefault(k, {'batch': s, 'members_in_batch': []})['members_in_batch'].append(oab)
    if i % 25 == 0:
        print(f'  {i}/{len(rows)}', file=sys.stderr)
    time.sleep(0.05)

print('sociedades distintas no lote:', len(soc_seen), file=sys.stderr)
for k, v in soc_seen.items():
    insc = str(int(v['batch']['inscricao'])) if v['batch'].get('inscricao', '').isdigit() else v['batch'].get('inscricao')
    st, body = get(f'/society/{insc}')
    e = {'batch': v['batch'], 'members_in_batch': v['members_in_batch'], 'http': st}
    if st == 200 and isinstance(body, dict):
        soc = body.get('society', body)
        e['db'] = {kk: soc.get(kk) for kk in ('id', 'name', 'state', 'inscricao', 'cnpj', 'number_of_partners', 'source', 'situacao')}
        e['db_members'] = [(m.get('oab_id'), m.get('full_name')) for m in (soc.get('lawyers') or soc.get('members') or [])]
        e['same_name'] = norm(soc.get('name')) == norm(v['batch']['name'])
        e['same_state'] = (soc.get('state') or '').upper() == (v['batch'].get('state') or '').upper()
        e['status'] = 'ok' if e['same_name'] and e['same_state'] else ('STATE_CONFLICT' if not e['same_state'] else 'NAME_DIFF')
    elif st == 404:
        e['status'] = 'new'
    else:
        e['status'] = f'error {st}'
        e['error'] = body if isinstance(body, str) else json.dumps(body)[:300]
    report['societies'][k] = e
    report['summary']['soc_' + e['status'].split()[0]] += 1
    time.sleep(0.05)

report['summary'] = dict(report['summary'])
json.dump(report, open(OUT, 'w'), ensure_ascii=False, indent=1)
print(json.dumps(report['summary'], ensure_ascii=False, indent=1))
