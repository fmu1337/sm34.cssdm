#!/usr/bin/env python3
"""Resolve a fmu1337/sourcemod-css34 line through its moving pointer release.

The fork deletes superseded rN releases, but keeps one pointer release per line
(line-sm12-latest, line-sm13-latest) with fixed asset names, SHA256SUMS and a
lines.json that names the release tag and the exact SourceMod / Metamod commits.

  css34_line.py <sm12|sm13> <dest_dir> [sourcemod] [mmsource]

downloads lines.json, SHA256SUMS and the requested packages into dest_dir, checks
them, and prints shell assignments (CSS34_TAG, CSS34_SM_COMMIT, CSS34_MM_COMMIT,
CSS34_SM_VERSION, CSS34_MM_VERSION, CSS34_EXT_API_MIN, CSS34_EXT_API_MAX,
CSS34_SOURCEMOD, CSS34_MMSOURCE). CSS34_POINTER overrides the pointer tag.
"""
import hashlib
import json
import os
import shlex
import sys
import time
import urllib.request

REPO = os.environ.get('CSS34_REPO', 'fmu1337/sourcemod-css34')
ASSETS = {'sourcemod': 'sourcemod-css34-linux.tar.gz', 'mmsource': 'mmsource-css34-linux.tar.gz'}


def fetch(url, path):
    for attempt in range(5):
        try:
            with urllib.request.urlopen(url, timeout=120) as r, open(path + '.part', 'wb') as f:
                f.write(r.read())
            os.replace(path + '.part', path)
            return
        except OSError as e:
            if attempt == 4:
                raise SystemExit('css34_line: %s: %s' % (url, e))
            time.sleep(3)


def main():
    line, dest, wanted = sys.argv[1], sys.argv[2], sys.argv[3:]
    pointer = os.environ.get('CSS34_POINTER') or 'line-%s-latest' % line
    base = 'https://github.com/%s/releases/download/%s/' % (REPO, pointer)
    os.makedirs(dest, exist_ok=True)
    for name in ['lines.json', 'SHA256SUMS'] + [ASSETS[w] for w in wanted]:
        fetch(base + name, os.path.join(dest, name))

    sums = {}
    for row in open(os.path.join(dest, 'SHA256SUMS')):
        parts = row.split()
        if len(parts) == 2:
            sums[parts[1].lstrip('*')] = parts[0]
    for w in wanted:
        name = ASSETS[w]
        got = hashlib.sha256(open(os.path.join(dest, name), 'rb').read()).hexdigest()
        if sums.get(name) != got:
            raise SystemExit('css34_line: %s sha256 %s != %s' % (name, got, sums.get(name)))

    info = json.load(open(os.path.join(dest, 'lines.json')))
    info = info.get('%s-latest' % line) or next(iter(info.values()))
    out = {
        'CSS34_POINTER': pointer,
        'CSS34_TAG': info['tag'],
        'CSS34_SM_COMMIT': info['sm_commit'],
        'CSS34_MM_COMMIT': info['mm_commit'],
        'CSS34_SM_VERSION': info['sm_version'],
        # "1.12.0-git1229" -> "1.12.0", as `meta version` prints "1.12.0-dev+1229"
        'CSS34_MM_VERSION': info['mm_version'].split('-')[0],
        'CSS34_EXT_API_MIN': str(info.get('extension_api_min', '')),
        'CSS34_EXT_API_MAX': str(info.get('extension_api', '')),
    }
    for w in wanted:
        out['CSS34_' + w.upper()] = os.path.abspath(os.path.join(dest, ASSETS[w]))
    for k, v in out.items():
        print('%s=%s' % (k, shlex.quote(v)))
    print('%s -> %s (SM %s %s, MM %s %s)' % (pointer, info['tag'], info['sm_version'], info['sm_commit'][:8],
                                            info['mm_version'], info['mm_commit'][:8]), file=sys.stderr)


if __name__ == '__main__':
    main()
