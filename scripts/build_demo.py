#!/usr/bin/env python3
# Builds docs/index.html (the demo page for GitHub Pages) from scripts/demo_template.html.
# Data, queries and test results are put directly into the page, so it works as one file.
# Needs a loaded database. Usage: python3 scripts/build_demo.py <github-username> [database]
import json, re, subprocess, sys, pathlib
root = pathlib.Path(__file__).resolve().parent.parent
user = sys.argv[1] if len(sys.argv) > 1 else 'shuyuanwang0502-eng'
db = sys.argv[2] if len(sys.argv) > 2 else 'hospital_infection'
repo = f'https://github.com/{user}/hospital-infection-control-db'
pages = f'https://{user}.github.io/hospital-infection-control-db/'

def psql(*args):
    return subprocess.run(['psql', '-X', '-d', db, *args], capture_output=True, text=True, check=True).stdout

# data as INSERT statements (skip psql commands and SET lines)
dump = subprocess.run(['pg_dump', '-d', db, '--data-only', '--inserts', '--rows-per-insert=1000',
                       '--no-owner', '--no-privileges'], capture_output=True, text=True, check=True).stdout
seed = '\n'.join(l for l in dump.splitlines()
                 if l and not l.startswith(('\\', '--', 'SET ', 'SELECT pg_catalog')))

# constraint tests + the error message postgres gives for each
rules = []
tests = (root / 'tests/constraint_tests.sql').read_text()
for rule, sql in re.findall(r"expect_reject\('([^']*)',\s*\$q\$(.*?)\$q\$\)", tests, re.S):
    sql = re.sub(r'\n\s+', '\n  ', sql.strip())
    r = subprocess.run(['psql', '-X', '-q', '-d', db, '-c', 'BEGIN', '-c', sql, '-c', 'ROLLBACK'], capture_output=True, text=True)
    pick = lambda tag: ' '.join(l.split(':', 1)[1].strip() for l in r.stderr.splitlines() if l.startswith(tag))
    rules.append(dict(rule=rule, sql=sql, error=pick('ERROR'), detail=pick('DETAIL')))

# table metadata
order = ['people', 'doctors', 'patients', 'infection_case', 'works_on', 'case_patient', 'tests', 'evidence_samples', 'sample_patient']
tables = []
for t in order:
    cols = json.loads(psql('-At', '-c', f"""
      SELECT json_agg(json_build_object('col', a.attname, 'type', format_type(a.atttypid, a.atttypmod),
        'null', NOT a.attnotnull,
        'pk', EXISTS (SELECT 1 FROM pg_constraint c WHERE c.conrelid = a.attrelid AND c.contype = 'p' AND a.attnum = ANY (c.conkey)),
        'fk', (SELECT string_agg(DISTINCT c.confrelid::regclass::text, ',') FROM pg_constraint c
               WHERE c.conrelid = a.attrelid AND c.contype = 'f' AND a.attnum = ANY (c.conkey))) ORDER BY a.attnum)
      FROM pg_attribute a WHERE a.attrelid = '{t}'::regclass AND a.attnum > 0 AND NOT a.attisdropped"""))
    rows = int(psql('-At', '-c', f'SELECT count(*) FROM {t}'))
    tables.append(dict(table_name=t, rows=rows, cols=cols))

queries = json.loads((root / 'docs/query_results.json').read_text())
svg = (root / 'docs/img/eer_diagram.svg').read_text()
svg = re.sub(r'\swidth="\d+" height="\d+"', '', svg, count=1)  # size is set in css

js = lambda o: json.dumps(o, ensure_ascii=False).replace('</', '<\\/')
page = (root / 'scripts/demo_template.html').read_text()
for key, val in {'/*__QUERIES__*/[]': js(queries), '/*__RULES__*/[]': js(rules), '/*__TABLES__*/[]': js(tables),
                 '/*__SCHEMA_SQL__*/""': js((root / 'sql/01_schema.sql').read_text()),
                 '/*__SEED_SQL__*/""': js(seed), '__EER_SVG__': svg, '__REPO_URL__': repo, '__PAGES_URL__': pages}.items():
    assert key in page, key
    page = page.replace(key, val)

body = page
(root / 'docs/.demo_fragment.html').write_text(body)
full = ('<!doctype html>\n<html lang="en">\n<head>\n<meta charset="utf-8">\n'
        '<meta name="viewport" content="width=device-width, initial-scale=1, viewport-fit=cover">\n'
        '<style>:root{padding-top:env(safe-area-inset-top,0px);padding-bottom:env(safe-area-inset-bottom,0px)}'
        'body{margin:0}img{max-width:100%}[hidden]{display:none!important}</style>\n'
        + body.replace('<header>', '</head>\n<body>\n<header>', 1) + '\n</body>\n</html>\n')
(root / 'docs/index.html').write_text(full)
print(f'docs/index.html written ({len(full)//1024} KB) for user {user}')
