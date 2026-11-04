#!/usr/bin/env python3
"""Upstream cssdm (alliedmodders/cssdm master) vs the `cssdm` submodule: bump and release helpers.

    upstream.py plan
        JSON {"behind": bool, "old": sha, "new": sha, "old_rev": N, "new_rev": N}.
    upstream.py apply <sha>
        Move the submodule to <sha> and check that the base patch config.json selects for
        its revision applies; exit 1 (with the reason) when it does not.
    upstream.py body <old> <new>
        Markdown PR body: upstream commits, which of them touch files our patch changes,
        gamedata keys the new code looks up that our v34 gamedata lacks.
    upstream.py version [--existing tags.txt]
        Release version of the current tree, as upstream names it: "2.1.6-git325", or
        "2.1.6-git325-r<N>" when that tag already exists (a rebuild of the same upstream rev).

Run from the repository root with the submodule's full history (git -C cssdm fetch --unshallow).
"""
import argparse
import json
import os
import re
import subprocess
import sys

ROOT = os.path.dirname(os.path.dirname(os.path.dirname(os.path.abspath(__file__))))
SUB = os.path.join(ROOT, 'cssdm')
UPSTREAM = 'https://github.com/alliedmodders/cssdm'
BRANCH = 'master'
PATCHES = os.path.join(ROOT, 'builder', 'patches')
GAMEDATA = os.path.join(PATCHES, '2.1', 'gamedata', 'cssdm.games.txt')
# Lookups the base patch compiles out on episode1 (CS:S v34 has no dominations / revenge).
NOT_ON_V34 = {'CalcDominationAndRevenge', 'CalcDomRevPatch', 'CalcDomRevPatch_'}


def git(*args, cwd=SUB, check=True):
    return subprocess.run(['git'] + list(args), cwd=cwd, check=check, capture_output=True, text=True).stdout.strip()


def pinned():
    return git('ls-tree', 'HEAD', 'cssdm', cwd=ROOT).split()[2]


def rev(sha):
    return int(git('rev-list', '--count', sha))


def fetch_upstream():
    git('fetch', '--quiet', UPSTREAM, BRANCH)
    return git('rev-parse', 'FETCH_HEAD')


def base_patch(revision):
    """The base patch config.json selects for this upstream revision (same rule as build.py)."""
    version = open(os.path.join(SUB, 'product.version')).readline().strip().split('-')[0]
    branch = '.'.join(version.split('.')[:2])
    config = json.load(open(os.path.join(ROOT, 'builder', 'run', 'config.json')))[branch]
    gates = sorted(int(k) for k in config if int(k) <= revision)
    if not gates:
        raise SystemExit('no config.json entry for {} rev {}'.format(branch, revision))
    return os.path.join(PATCHES, branch, config[str(gates[-1])]['patch'])


def patched_files(patch):
    return sorted(set(re.findall(r'^diff --git a/(\S+) ', open(patch, encoding='utf-8', errors='replace').read(), re.M)))


def cmd_plan(_):
    old, new = pinned(), fetch_upstream()
    behind = old != new
    if behind and subprocess.run(['git', 'merge-base', '--is-ancestor', old, new], cwd=SUB).returncode != 0:
        raise SystemExit('upstream {} is not a descendant of the pinned {}'.format(new, old))
    print(json.dumps({'behind': behind, 'old': old, 'new': new, 'old_rev': rev(old), 'new_rev': rev(new)}))


def cmd_apply(args):
    git('checkout', '--quiet', args.sha)
    git('submodule', 'update', '--init', '--recursive', '--quiet')
    patch = base_patch(rev(args.sha))
    check = subprocess.run(['git', 'apply', '--check', '--ignore-space-change', '--ignore-whitespace', patch],
                           cwd=SUB, capture_output=True, text=True)
    git('add', 'cssdm', cwd=ROOT)
    if check.returncode != 0:
        sys.stdout.write(check.stderr)
        raise SystemExit('{} does not apply to {} (rev {})'.format(os.path.relpath(patch, ROOT), args.sha[:12], rev(args.sha)))
    print('{} applies to {} (rev {})'.format(os.path.relpath(patch, ROOT), args.sha[:12], rev(args.sha)))


def lookups(sha):
    """Gamedata names the extension and plugins at <sha> look up."""
    names = set()
    for path in git('ls-tree', '-r', '--name-only', sha).splitlines():
        if not re.search(r'\.(cpp|h|sp|inc)$', path):
            continue
        text = git('show', '{}:{}'.format(sha, path))
        names |= set(re.findall(r'(?:GetOffset|GetMemSig|GetKeyValue|GetAddress)\(\s*"([^"]+)"', text))
        names |= set(re.findall(r'SetFromConf\([^,]+,\s*SDKConf_\w+,\s*"([^"]+)"', text))
        names |= set(re.findall(r'GameConf(?:GetOffset|GetKeyValue|GetAddress)\([^,]+,\s*"([^"]+)"', text))
        # Keys built at runtime ("<name>_" PLATFORM_NAME) are checked by their prefix.
        names |= {n + '_' for n in re.findall(r'DM_FFA_LoadPatch\(\s*"([^"]+)"', text)}
    return names


def missing_gamedata(sha):
    ours = open(GAMEDATA, encoding='utf-8', errors='replace').read()
    out = []
    for name in sorted(lookups(sha) - NOT_ON_V34):
        if name.endswith('_'):
            if ('"' + name) not in ours:
                out.append(name + '<platform>')
        elif ('"' + name + '"') not in ours:
            out.append(name)
    return out


def cmd_body(args):
    old, new = args.old, args.new
    patch = base_patch(rev(new))
    ours = set(patched_files(patch))
    lines = ['Upstream `alliedmodders/cssdm` {}: `{}` (git{}) → `{}` (git{}).'.format(
                 BRANCH, old[:8], rev(old), new[:8], rev(new)),
             '', '{}/compare/{}...{}'.format(UPSTREAM, old, new), '',
             '| Commit | Subject | Touches our patch |', '|---|---|---|']
    for row in git('log', '--reverse', '--no-merges', '--format=%H%x1f%s', '{}..{}'.format(old, new)).splitlines():
        sha, subject = row.split('\x1f', 1)
        files = set(git('show', '--format=', '--name-only', sha).splitlines())
        hit = sorted(files & ours)
        lines.append('| `{}` | {} | {} |'.format(sha[:8], subject.replace('|', '/'),
                                               ', '.join('`{}`'.format(f) for f in hit) or '—'))
    lines += ['', 'Base patch: `{}` (selected by `builder/run/config.json` for git{}).'.format(
        os.path.relpath(patch, ROOT).replace(os.sep, '/'), rev(new))]
    missing = missing_gamedata(new)
    if missing:
        lines += ['', '**v34 gamedata is missing keys the new code looks up** '
                  '(`builder/patches/2.1/gamedata/cssdm.games.txt`): ' + ', '.join('`{}`'.format(m) for m in missing)
                  + '. Add CS:S v34 values found in the v34 binaries, not guessed ones.']
    else:
        lines += ['', 'Gamedata: every key the new code looks up exists in the v34 gamedata.']
    print('\n'.join(lines))


def cmd_version(args):
    base = open(os.path.join(SUB, 'product.version')).readline().strip().replace('-dev', '')
    version = '{}-git{}'.format(base, rev('HEAD'))
    existing = set(open(args.existing).read().split()) if args.existing and os.path.isfile(args.existing) else set()
    if 'v' + version in existing:
        n = 2
        while 'v{}-r{}'.format(version, n) in existing:
            n += 1
        version = '{}-r{}'.format(version, n)
    print(version)


def main():
    ap = argparse.ArgumentParser(description=__doc__.splitlines()[0])
    sub = ap.add_subparsers(dest='cmd', required=True)
    sub.add_parser('plan')
    p = sub.add_parser('apply')
    p.add_argument('sha')
    p = sub.add_parser('body')
    p.add_argument('old')
    p.add_argument('new')
    p = sub.add_parser('version')
    p.add_argument('--existing')
    args = ap.parse_args()
    {'plan': cmd_plan, 'apply': cmd_apply, 'body': cmd_body, 'version': cmd_version}[args.cmd](args)


if __name__ == '__main__':
    main()
