#!/usr/bin/env python3
"""What cssdm patches / calls in the v34 server_i486.so.

Usage: inspect-server.py <server_i486.so> <check-css34-vtables.py from sourcemod-css34>

Prints, from the binary itself (symbols + relocations):
  - the symbols cssdm.games resolves,
  - which method sits in CCSGameRules vtable slot "IPointsForKill" (64) and
    CCSPlayer slot "RemoveAllItems" (284), plus their sizes,
  - the instructions at the FFA patch sites (function + gamedata offset),
  - the whole IPointsForKill body (what the plugin overwrites with mov eax,1; ret).
Exits 1 if something cssdm relies on does not match.
"""
import importlib.machinery
import subprocess
import sys

so, helper = sys.argv[1], sys.argv[2]
vt = importlib.machinery.SourceFileLoader('vt', helper).load_module()

elf = vt.Elf32(so)
syms = {}
for sec in elf.sections:
    if sec['type'] in (2, 11):
        for name, value, size, typ in elf.symbols(sec):
            if name and value:
                syms.setdefault(name, (value, size))
by_addr = {}
for name, (value, size) in syms.items():
    by_addr.setdefault(value, (name, size))

fail = 0


def demangle(name):
    return subprocess.run(['c++filt', name], capture_output=True, text=True).stdout.strip()


def objdump(start, stop):
    out = subprocess.run(['objdump', '-d', '-w', '-M', 'intel',
                          '--start-address=%#x' % start, '--stop-address=%#x' % stop, so],
                         capture_output=True, text=True).stdout
    return [l for l in out.splitlines() if l[:1] == ' ' and ':' in l]


print('== symbols used by cssdm.games (linux)')
for s in ['g_pGameRules', '_ZN9CCSPlayer12RoundRespawnEv',
          '_ZN9CCSPlayer12OnTakeDamageERK15CTakeDamageInfo',
          '_ZNK11CBasePlayer28WantsLagCompensationOnEntityEPKS_PK8CUserCmdPK7CBitVecILi2048EE']:
    if s in syms:
        print('  OK   %-40s %#x size %d' % (demangle(s)[:40], syms[s][0], syms[s][1]))
    else:
        print('  MISS %s' % s)
        fail = 1

tables = vt.load_vtables(so, ['_ZTV12CCSGameRules', '_ZTV9CCSPlayer'])

print('== vtable slots')
for table, slot, want in [('_ZTV12CCSGameRules', 64, 'IPointsForKill'),
                          ('_ZTV9CCSPlayer', 284, 'RemoveAllItems'),
                          ('_ZTV12CCSGameRules', 115, 'GoToIntermission')]:
    name = tables[table][slot]
    dem = demangle(name)
    ok = want in dem
    fail |= not ok
    size = syms.get(name, (0, 0))[1]
    print('  %s %s[%d] = %s (%d bytes)' % ('OK  ' if ok else 'FAIL', table, slot, dem, size))
    if want == 'IPointsForKill':
        points = name
        # neighbours, to see the slot is not off by one
        for s in (slot - 1, slot + 1):
            print('       [%d] = %s' % (s, demangle(tables[table][s])))

print('== FFA patch sites (function + offset, bytes replaced)')
for func, off, n, label in [
        ('_ZNK11CBasePlayer28WantsLagCompensationOnEntityEPKS_PK8CUserCmdPK7CBitVecILi2048EE', 62, 6, 'LagCompPatch'),
        ('_ZN9CCSPlayer12OnTakeDamageERK15CTakeDamageInfo', 1547, 6, 'TakeDmgPatch1')]:
    base = syms[func][0]
    site = base + off
    print('  %s: %s + %d = %#x, %d bytes -> 90 x%d' % (label, demangle(func).split('(')[0], off, site, n, n))
    lines = objdump(site - 24, site + n + 16)
    for l in lines:
        addr = int(l.split(':')[0], 16)
        mark = '>>' if site <= addr < site + n else '  '
        print('    ' + mark + l)
    starts = [int(l.split(':')[0], 16) for l in lines]
    if site not in starts or (site + n) not in starts:
        print('    FAIL: patch does not cover whole instructions')
        fail = 1

print('== IPointsForKill body (plugin writes B8 01 00 00 00 C3 at its start)')
base, size = syms[points]
print('  %s at %#x, %d bytes' % (demangle(points), base, size))
for l in objdump(base, base + size):
    print('    ' + l)
if size < 6:
    print('  FAIL: shorter than the 6-byte patch')
    fail = 1

# Who else calls IPointsForKill directly (not through the vtable)? Those calls
# would be affected by a body patch but not by the extension's vtable hook.
print('== direct calls to IPointsForKill')
out = subprocess.run(['objdump', '-d', '-w', so], capture_output=True, text=True).stdout
cur = None
hits = []
for l in out.splitlines():
    if l.endswith('>:'):
        cur = l.split('<', 1)[1][:-2]
    elif ('call' in l) and ('<%s' % points) in l:
        hits.append(cur)
print('  %d direct call(s)%s' % (len(hits), ''.join('\n    from ' + demangle(h) for h in hits)))

print('RESULT', 'FAIL' if fail else 'OK')
sys.exit(fail)
