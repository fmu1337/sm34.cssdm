#!/usr/bin/env python3
"""Boot srcds once for the CSS:DM compatibility table.

Prints MM/SM versions and the extension/plugin lists, records which ep1 binaries
are mapped, lets bots play for BOT_SECS, lists extensions again and quits. The
console (a pty, as an operator would see it) goes to COMPAT_LOG.

env: SERVER_DIR, COMPAT_LOG, MAPS_FILE, MAP (de_dust2), PORT (27015),
     SRCDS_BINARY (./srcds_i686), SRCDS_PREFIX (e.g. "FEX" on ARM), BOT_SECS (90),
     MAP_TIMEOUT (180)
"""
import os
import pty
import re
import subprocess
import sys
import threading
import time

env = os.environ
server_dir, log_path, maps_path = env['SERVER_DIR'], env['COMPAT_LOG'], env['MAPS_FILE']
game_map = env.get('MAP') or 'de_dust2'
bot_secs = int(env.get('BOT_SECS') or 90)

cmd = (env.get('SRCDS_PREFIX') or '').split() + [
    env.get('SRCDS_BINARY') or './srcds_i686', '-game', 'cstrike', '-console', '-nohltv', '-nomaster',
    '-localcser', '-tickrate', '66', '-ip', '127.0.0.1', '-port', env.get('PORT') or '27015',
    '+ip', '127.0.0.1', '+sv_lan', '1', '+maxplayers', '16', '+log', 'on', '+sv_logecho', '1',
    '+map', game_map]
run_env = dict(env, LD_LIBRARY_PATH='.:bin:' + env.get('LD_LIBRARY_PATH', ''))

master, slave = pty.openpty()
proc = subprocess.Popen(cmd, cwd=server_dir, env=run_env, stdin=slave, stdout=slave, stderr=slave,
                        start_new_session=True)
os.close(slave)
out = []
log = open(log_path, 'w', encoding='utf-8', errors='replace')


def reader():
    while True:
        try:
            data = os.read(master, 65536)
        except OSError:
            break
        if not data:
            break
        text = data.decode('utf-8', 'replace')
        out.append(text)
        log.write(text)
        log.flush()


threading.Thread(target=reader, daemon=True).start()


def finish(code, msg):
    print('COMPAT: ' + msg, flush=True)
    if proc.poll() is None:
        proc.kill()
    time.sleep(1)
    log.close()
    sys.exit(code)


deadline = time.time() + int(env.get('MAP_TIMEOUT') or 180)
pat = re.compile(r'Mapchange to %s|Loading map "%s"|Started map "%s"' % ((re.escape(game_map),) * 3))
while not pat.search(''.join(out)):
    if proc.poll() is not None:
        finish(2, 'exited before map (rc %s)' % proc.returncode)
    if time.time() > deadline:
        finish(2, 'timeout waiting for map')
    time.sleep(1)
time.sleep(5)


def send(line, wait=2):
    os.write(master, (line + '\n').encode())
    end = time.time() + wait
    while time.time() < end:
        if proc.poll() is not None:
            finish(3, "exited after '%s' (rc %s)" % (line, proc.returncode))
        time.sleep(0.5)


send('meta version')
send('sm version')
send('echo COMPAT_EXTS_BEGIN')
send('sm exts list', 3)
send('echo COMPAT_PLUGINS_BEGIN')
send('sm plugins list', 3)
send('echo COMPAT_LISTS_END')

# The ep1 binaries actually mapped (under FEX the guest's files show up in the host process).
mapped = set()
pids = [str(proc.pid)] + subprocess.run(['pgrep', '-g', str(proc.pid)], capture_output=True,
                                        text=True).stdout.split()
for pid in pids:
    try:
        mapped |= set(re.findall(r'(?:metamod|sourcemod|cssdm\.ext)\.[0-9]\.ep1\.so',
                                 open('/proc/%s/maps' % pid).read()))
    except OSError:
        pass
open(maps_path, 'w').write('\n'.join(sorted(mapped)) + '\n')

for c in ('bot_join_after_player 0', 'bot_quota_mode fill', 'bot_difficulty 2', 'bot_chatter off', 'bot_quota 8'):
    send(c, 1)
send('echo COMPAT_BOTS_BEGIN')
send('mp_restartgame 1', bot_secs)
send('echo COMPAT_BOTS_END')
send('echo COMPAT_EXTS_AFTER')
send('sm exts list', 3)
send('status', 2)

os.write(master, b'quit\n')
try:
    proc.wait(timeout=30)
except subprocess.TimeoutExpired:
    pass
finish(0, 'done')
