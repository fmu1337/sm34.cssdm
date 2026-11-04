#!/usr/bin/env python3
"""Expand testing/compat/sm-builds.json into concrete Metamod + SourceMod downloads.

Entries with "pointer" (sm11 / sm12 / sm13) are resolved through the fork's moving
pointer release (builder/run/css34_line.py): URLs and sha256 come from its SHA256SUMS
and the release tag is appended to the label. Entries with "mm"/"sm" are used as
given; "local" entries are passed through for compat-local.sh.

  compat-builds.py <sm-builds.json> [--ci]

prints a JSON list of {id, group, label, local, mm_url, mm_sha, sm_url, sm_sha};
--ci leaves out the "local" entries.
"""
import json
import os
import sys
import tempfile

ROOT = os.path.dirname(os.path.dirname(os.path.dirname(os.path.abspath(__file__))))
sys.path.insert(0, os.path.join(ROOT, 'builder', 'run'))
import css34_line  # noqa: E402


def main():
    path, ci = sys.argv[1], '--ci' in sys.argv[2:]
    out = []
    with tempfile.TemporaryDirectory() as tmp:
        for b in json.load(open(path, encoding='utf-8'))['builds']:
            if 'local' in b:
                if not ci:
                    out.append({'id': b['id'], 'group': b['group'], 'label': b['label'], 'local': b['local']})
                continue
            row = {'id': b['id'], 'group': b['group'], 'label': b['label'], 'local': ''}
            if 'pointer' in b:
                mm = b.get('mm_asset', 'mmsource')
                r = css34_line.resolve(b['pointer'], os.path.join(tmp, b['id']), ['sourcemod', mm], download=False)
                mv = css34_line.var(mm)
                row.update(label='%s (%s)' % (b['label'], r['CSS34_TAG']),
                           mm_url=r[mv + '_URL'], mm_sha=r[mv + '_SHA256'],
                           sm_url=r['CSS34_SOURCEMOD_URL'], sm_sha=r['CSS34_SOURCEMOD_SHA256'])
            else:
                row.update(mm_url=b['mm']['url'], mm_sha=b['mm']['sha256'],
                           sm_url=b['sm']['url'], sm_sha=b['sm']['sha256'])
            out.append(row)
    print(json.dumps(out))


if __name__ == '__main__':
    main()
