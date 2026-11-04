#!/usr/bin/env python3
"""Resolve a fmu1337/sourcemod-css34 line through its moving pointer release.

The fork deletes superseded rN releases, but keeps one pointer release per line
(line-sm11-oldstable, line-sm12-latest, line-sm13-latest) with fixed asset names,
SHA256SUMS and a lines.json that names the release tag and the exact SourceMod /
Metamod commits.

  css34_line.py [--urls] <sm11|sm12|sm13> <dest_dir> [sourcemod] [mmsource] [mmsource-legacy]

downloads lines.json, SHA256SUMS and the requested packages into dest_dir, checks
them, and prints shell assignments (CSS34_TAG, CSS34_SM_COMMIT, CSS34_MM_COMMIT,
CSS34_SM_VERSION, CSS34_MM_VERSION, CSS34_EXT_API_MIN, CSS34_EXT_API_MAX, and
CSS34_SOURCEMOD / CSS34_MMSOURCE / CSS34_MMSOURCE_LEGACY paths). With --urls the
packages are not downloaded; CSS34_<ASSET>_URL and CSS34_<ASSET>_SHA256 are printed
instead. CSS34_POINTER overrides the pointer tag.
"""
import hashlib
import json
import os
import shlex
import sys
import time
import urllib.request

REPO = os.environ.get('CSS34_REPO', 'fmu1337/sourcemod-css34')
LINES = {'sm11': 'sm11-oldstable', 'sm12': 'sm12-latest', 'sm13': 'sm13-latest'}
ASSETS = {
    'sourcemod': 'sourcemod-css34-linux.tar.gz',
    'mmsource': 'mmsource-css34-linux.tar.gz',
    'mmsource-legacy': 'mmsource-legacy-css34-linux.tar.gz',
}


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


def var(asset):
    return 'CSS34_' + asset.upper().replace('-', '_')


def resolve(line, dest, wanted, download=True):
    """Shell-variable dict for a line's pointer release (see module docstring)."""
    full = LINES.get(line, line)
    pointer = os.environ.get('CSS34_POINTER') or 'line-%s' % full
    base = 'https://github.com/%s/releases/download/%s/' % (REPO, pointer)
    os.makedirs(dest, exist_ok=True)
    for name in ['lines.json', 'SHA256SUMS'] + ([ASSETS[w] for w in wanted] if download else []):
        fetch(base + name, os.path.join(dest, name))

    sums = {}
    for row in open(os.path.join(dest, 'SHA256SUMS')):
        parts = row.split()
        if len(parts) == 2:
            sums[parts[1].lstrip('*')] = parts[0]

    info = json.load(open(os.path.join(dest, 'lines.json')))
    info = info.get(full) or next(iter(info.values()))
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
        name = ASSETS[w]
        if name not in sums:
            raise SystemExit('css34_line: %s has no %s' % (pointer, name))
        if download:
            got = hashlib.sha256(open(os.path.join(dest, name), 'rb').read()).hexdigest()
            if sums[name] != got:
                raise SystemExit('css34_line: %s sha256 %s != %s' % (name, got, sums[name]))
            out[var(w)] = os.path.abspath(os.path.join(dest, name))
        else:
            out[var(w) + '_URL'] = base + name
            out[var(w) + '_SHA256'] = sums[name]
    print('%s -> %s (SM %s %s, MM %s %s)' % (pointer, info['tag'], info['sm_version'], info['sm_commit'][:8],
                                            info['mm_version'], info['mm_commit'][:8]), file=sys.stderr)
    return out


def main():
    args = sys.argv[1:]
    download = True
    if args and args[0] == '--urls':
        download = False
        args = args[1:]
    for k, v in resolve(args[0], args[1], args[2:], download).items():
        print('%s=%s' % (k, shlex.quote(v)))


if __name__ == '__main__':
    main()
