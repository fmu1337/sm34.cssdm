#!/usr/bin/env python3
"""CSS:DM compatibility table.

  parse  turn one compat-run.py console log into a JSON result line (stdout)
  table  render result lines as a Markdown table (rows: SM builds, columns: CSS:DM variants)
"""
import argparse
import glob
import json
import os
import re
import sys

DM_PLUGINS = 5
CSSDM_ORDER = ['none', 'sm11', 'sm12', 'sm13']
CSSDM_TITLES = {
    'none': 'no cssdm (SM itself)',
    'sm11': 'cssdm sm11 (API 8, 1.ep1+2.ep1)',
    'sm12': 'cssdm sm12 (API 8, 2.ep1)',
    'sm13': 'cssdm sm13 (API 11, 2.ep1)',
}


def section(text, start, end=None):
    """Console output between an `echo` marker line and the next marker."""
    m = re.search(r'^%s\s*$' % start, text, re.M)
    if not m:
        return ''
    rest = text[m.end():]
    if end:
        e = re.search(r'^%s\s*$' % end, rest, re.M)
        if e:
            rest = rest[:e.start()]
    return rest


def parse(args):
    text = ''
    if os.path.isfile(args.console):
        text = open(args.console, encoding='utf-8', errors='replace').read().replace('\r', '')
    expect_out = open(args.runner_out, encoding='utf-8', errors='replace').read() if os.path.isfile(args.runner_out) else ''
    mapped = open(args.maps).read().split() if os.path.isfile(args.maps) else []

    r = {'sm_id': args.sm_id, 'sm_label': args.sm_label, 'cssdm_id': args.cssdm_id, 'rc': args.rc,
         'runner': args.runner}
    m = re.search(r'Metamod:Source [Vv]ersion:? (\d\S*)', text)
    r['mm_version'] = m.group(1) if m else None
    m = re.search(r'SourceMod Version: (\S+)', text)
    r['sm_version'] = m.group(1) if m else None
    r['map_loaded'] = 'exited before map' not in expect_out and 'timeout waiting for map' not in expect_out
    r['mapped'] = sorted(set(mapped))
    r['sm_core'] = next((x for x in r['mapped'] if x.startswith('sourcemod.')), None)
    r['cssdm_file'] = next((x for x in r['mapped'] if x.startswith('cssdm.ext.')), None)

    exts = section(text, 'COMPAT_EXTS_BEGIN', 'COMPAT_PLUGINS_BEGIN')
    m = re.search(r'\] CS:S DM \(([^)]*)\)', exts)
    f = re.search(r'<FAILED> file "(cssdm[^"]*)": *(.*)', exts)
    if m:
        r['cssdm'] = 'loaded'
        r['cssdm_version'] = m.group(1)
    elif f:
        r['cssdm'] = 'failed'
        r['cssdm_error'] = '%s: %s' % (f.group(1), f.group(2).strip())
    else:
        r['cssdm'] = 'missing'

    plugins = section(text, 'COMPAT_PLUGINS_BEGIN', 'COMPAT_LISTS_END')
    r['dm_running'] = len(re.findall(r'^\s*\d+ "CS:S DM', plugins, re.M))
    r['dm_failed'] = len(re.findall(r'<(?:Failed|Error|Bad Load)> (?:"CS:S DM|cssdm/)', plugins))
    errs = re.findall(r'cssdm/(\w+)\.smx[^:\n]*: ([^\n]+)', plugins)
    r['dm_errors'] = sorted(set(e for _, e in errs))[:3]

    bots = section(text, 'COMPAT_BOTS_BEGIN', 'COMPAT_BOTS_END')
    kills = len(re.findall(r'" killed "', bots))
    if args.logs_dir and os.path.isdir(args.logs_dir):
        log_kills = 0
        for lf in glob.glob(os.path.join(args.logs_dir, 'L*.log')):
            log_kills += len(re.findall(r'" killed "', open(lf, encoding='utf-8', errors='replace').read()))
        kills = max(kills, log_kills)
    r['kills'] = kills
    after = section(text, 'COMPAT_EXTS_AFTER')
    r['cssdm_after_bots'] = bool(re.search(r'\] CS:S DM \(', after))
    r['crashed'] = 'COMPAT: done' not in expect_out
    crash_line = re.search(r'COMPAT: (exited[^\n]*|timeout[^\n]*)', expect_out)
    r['crash_note'] = crash_line.group(1) if crash_line else None
    r['ok'] = bool(r['cssdm'] == 'loaded' and r['dm_running'] == DM_PLUGINS and r['kills'] > 0
                   and r['cssdm_after_bots'] and not r['crashed'])
    print(json.dumps(r, ensure_ascii=False))


def short_error(err):
    """cssdm.ext load error without absolute paths; a missing 1.ep1 binary named as such."""
    name, _, why = err.partition(': ')
    if name == 'cssdm.ext.so' and 'cannot open shared object file' in why:
        return 'no binary for the 1.ep1 core'
    why = re.sub(r'/\S*/', '', why)
    return '`%s: %s`' % (name, why.replace('|', '/')[:90])


def cell(r):
    tag = ' (FEX)' if r.get('runner') == 'fex' else ''
    return base_cell(r) + tag


def base_cell(r):
    if not r['map_loaded']:
        return 'server did not start'
    if r['cssdm_id'] == 'none':
        if r['crashed']:
            return '**crash** (%s)' % (r.get('crash_note') or 'no clean exit')
        return 'runs, %d kills' % r['kills']
    if r['crashed'] and r['cssdm'] != 'loaded':
        return '**crash** (%s)' % (r.get('crash_note') or 'no clean exit')
    if r['cssdm'] == 'failed':
        return 'no: ' + short_error(r['cssdm_error'])
    if r['cssdm'] == 'missing':
        return 'no: cssdm.ext not listed'
    parts = [r.get('cssdm_file') or 'loaded', 'plugins %d/%d' % (r['dm_running'], DM_PLUGINS),
             '%d kills' % r['kills']]
    if r['crashed']:
        parts.append('**crash** (%s)' % (r.get('crash_note') or 'no clean exit'))
    elif not r['cssdm_after_bots']:
        parts.append('gone after bots')
    if r['dm_errors']:
        parts.append('`%s`' % r['dm_errors'][0][:60])
    return ('yes: ' if r['ok'] else 'partial: ') + ', '.join(parts)


def table(args):
    rows = []
    for path in args.results:
        for line in open(path, encoding='utf-8'):
            if line.strip():
                rows.append(json.loads(line))
    builds = json.load(open(args.builds, encoding='utf-8'))['builds']
    order = {b['id']: i for i, b in enumerate(builds)}
    groups = {b['id']: b['group'] for b in builds}
    present = [c for c in CSSDM_ORDER if any(r['cssdm_id'] == c for r in rows)]
    present += sorted(set(r['cssdm_id'] for r in rows) - set(present))
    by = {}
    for r in rows:
        by[(r['sm_id'], r['cssdm_id'])] = r

    out = ['| Source | Build | MM / SM seen | SM core |' + ''.join(' %s |' % CSSDM_TITLES.get(c, c) for c in present),
           '|---|---|---|---|' + '---|' * len(present)]
    for sm_id in sorted(set(r['sm_id'] for r in rows), key=lambda x: order.get(x, 99)):
        mine = [r for r in rows if r['sm_id'] == sm_id]
        any_r = next((r for r in mine if r.get('sm_version')), mine[0])
        cores = sorted(set(by[(sm_id, c)]['sm_core'] for c in present if (sm_id, c) in by and by[(sm_id, c)]['sm_core']))
        seen = '%s / %s' % (any_r.get('mm_version') or '?', any_r.get('sm_version') or '?')
        line = '| %s | %s | %s | %s |' % (groups.get(sm_id, '?'), any_r['sm_label'], seen, ', '.join(cores) or '?')
        for c in present:
            line += ' %s |' % (cell(by[(sm_id, c)]) if (sm_id, c) in by else 'not run')
        out.append(line)
    print('\n'.join(out))


def main():
    ap = argparse.ArgumentParser()
    sub = ap.add_subparsers(dest='cmd', required=True)
    p = sub.add_parser('parse')
    for a in ('--sm-id', '--sm-label', '--cssdm-id', '--console', '--maps', '--runner-out', '--logs-dir'):
        p.add_argument(a, default='')
    p.add_argument('--rc', type=int, default=0)
    p.add_argument('--runner', default='')
    t = sub.add_parser('table')
    t.add_argument('--builds', required=True)
    t.add_argument('results', nargs='+')
    args = ap.parse_args()
    parse(args) if args.cmd == 'parse' else table(args)


if __name__ == '__main__':
    sys.exit(main())
