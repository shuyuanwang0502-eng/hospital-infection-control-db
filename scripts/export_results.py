#!/usr/bin/env python3
# Runs all queries from sql/03_queries.sql and saves the results to
# docs/query_results.md and docs/query_results.json (the json is used by the demo page).
# Needs a loaded database. Usage: python3 scripts/export_results.py [database]
import csv, io, json, re, subprocess, sys, pathlib
root = pathlib.Path(__file__).resolve().parent.parent
db = sys.argv[1] if len(sys.argv) > 1 else 'hospital_infection'
text = (root / 'sql/03_queries.sql').read_text()
blocks = re.split(r'(?m)^-- (Query \d+(?::.*)?)$', text)[1:]
queries = []
for head, body in zip(blocks[::2], blocks[1::2]):
    lines = body.strip('\n').split('\n')
    desc, sql = [], []
    for ln in lines:
        if not sql and ln.startswith('--'):
            desc.append(ln[2:].strip())
        elif ln.startswith('-- extra queries'):
            break
        else:
            sql.append(ln)
    sql = '\n'.join(sql).strip()
    out = subprocess.run(['psql', '-X', '-q', '--csv', '-v', 'ON_ERROR_STOP=1', '-d', db, '-c', sql],
                         capture_output=True, text=True, check=True).stdout
    rows = list(csv.reader(io.StringIO(out)))
    num = int(re.search(r'\d+', head).group())
    title = head.split(':', 1)[1].strip() if ':' in head else ''
    k = next((i for i, d in enumerate(desc) if d.startswith('Uses:')), len(desc))
    question = ' '.join(d for d in desc[:k] if d)
    technique = ' '.join(desc[k:]).replace('Uses:', '').strip()
    queries.append(dict(n=num, title=title, question=question, technique=technique,
                        sql=sql, columns=rows[0], rows=rows[1:]))
(root / 'docs/query_results.json').write_text(json.dumps(queries, indent=1, ensure_ascii=False))
md = ['# Query results', '',
      'Output of every query in sql/03_queries.sql (made with scripts/export_results.py).', '']
for q in queries:
    md += [f"## Query {q['n']}" + (f": {q['title']}" if q['title'] else ''), '', q['question'], '']
    if q['technique']: md += [f"Uses: {q['technique']}", '']
    md += ['```sql', q['sql'], '```', '']
    shown = q['rows'][:15]
    md += ['| ' + ' | '.join(q['columns']) + ' |', '|' + '---|' * len(q['columns'])]
    md += ['| ' + ' | '.join(r) + ' |' for r in shown]
    if len(q['rows']) > 15: md += ['', f"({len(q['rows'])} rows, first 15 shown)"]
    else: md += ['', f"({len(q['rows'])} rows)"]
    md += ['']
(root / 'docs/query_results.md').write_text('\n'.join(md))
print(f'exported {len(queries)} queries')
