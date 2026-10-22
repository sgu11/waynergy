#!/usr/bin/env python3
"""Exercise screen hooks and failure recovery using a real Waynergy client.

Run in an active Hyprland session. Temporarily changes cursor visibility;
keeps the pointer position and sends no keyboard, clipboard, or lock events.
Usage: python3 scripts/verify-cursor-sync.py [--render] [BINARY] [HELPER]
"""
import argparse
import io
import json
from pathlib import Path
import socket
import struct
import subprocess
import sys
import tempfile
import time
import uuid


def run(*args):
    return subprocess.check_output(args, text=True).strip()


def visibility(expected):
    deadline = time.monotonic() + 5
    while time.monotonic() < deadline:
        state = json.loads(run('hyprctl', '-j', 'getoption', 'cursor:invisible'))
        if state['bool'] is expected:
            return
        time.sleep(0.005)
    raise AssertionError(f'cursor:invisible did not become {expected}')


def rendered_visibility(expected, timeout, start=None):
    # Inspect only the small cursor region in memory; never save screen images.
    from PIL import Image, ImageChops

    position = json.loads(run('hyprctl', '-j', 'cursorpos'))
    geometry = f"{max(0, position['x'] - 4)},{max(0, position['y'] - 4)} 48x48"
    if start is None:
        start = time.monotonic()
    while time.monotonic() - start < timeout:
        captures = []
        for cursor in (False, True):
            args = ['grim', '-g', geometry]
            if cursor:
                args.append('-c')
            captures.append(Image.open(io.BytesIO(subprocess.check_output([*args, '-']))).convert('RGB'))
        assert json.loads(run('hyprctl', '-j', 'cursorpos')) == position, 'pointer moved during render check'
        difference = ImageChops.difference(*captures).convert('L')
        pixels = sum(difference.histogram()[20:])
        if (pixels > 20) is expected:
            elapsed = (time.monotonic() - start) * 1000
            assert elapsed <= timeout * 1000, f'rendered cursor exceeded {timeout * 1000:.0f} ms'
            print(f'PASS: rendered cursor visible={expected} within {elapsed:.1f} ms', flush=True)
            return
    raise AssertionError(f'rendered cursor visible={expected} exceeded {timeout * 1000:.0f} ms')


def receive(sock, count):
    data = b''
    while len(data) < count:
        chunk = sock.recv(count - len(data))
        if not chunk:
            raise AssertionError('client disconnected before hello reply')
        data += chunk
    return data


def send(sock, body):
    sock.sendall(struct.pack('!I', len(body)) + body)


if __name__ == '__main__':
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument('--render', action='store_true', help='check actual rendering with grim/Pillow; briefly stop the live client')
    parser.add_argument('binary', nargs='?', default='/usr/bin/waynergy')
    parser.add_argument('helper', nargs='?', default=str(Path.home() / '.local/bin/waynergy-cursor'))
    args = parser.parse_args()
    binary = str(Path(args.binary).resolve())
    helper = str(Path(args.helper).resolve())
    resume_live = args.render and subprocess.run(
        ['systemctl', '--user', 'is-active', '--quiet', 'waynergy.service']).returncode == 0
    if resume_live:
        run('systemctl', '--user', 'stop', 'waynergy.service')
    unit = 'waynergy-cursor-check-' + uuid.uuid4().hex + '.service'
    original = json.loads(run('hyprctl', '-j', 'getoption', 'cursor:invisible'))['bool']
    original_timeout = json.loads(run('hyprctl', '-j', 'getoption', 'cursor:inactive_timeout'))['float']
    original_position = json.loads(run('hyprctl', '-j', 'cursorpos'))
    with tempfile.TemporaryDirectory(prefix='waynergy-cursor-check-') as directory, socket.socket() as server:
        config = Path(directory)
        (config / 'config.ini').write_text(
            '[idle-inhibit]\nenable=false\n[screen]\n'
            f'enter="{helper}" show\nexit="{helper}" hide\n')
        server.bind(('127.0.0.1', 0))
        server.listen(1)
        server.settimeout(10)
        try:
            if args.render:
                plugin = Path.home() / '.local/lib/waynergy/waynergy-cursor-refresh.so'
                reply = run('hyprctl', 'plugin', 'unload', str(plugin.resolve()))
                assert reply == 'ok', reply
                run(helper, 'init')
                print('PASS: native cursor plugin unload/reload and callback registration', flush=True)
            run('systemd-run', '--user', '--quiet', '--collect', '--unit=' + unit,
                '--property=Type=exec', '--property=ExecStartPre=' + helper + ' show',
                '--property=ExecStopPost=' + helper + ' show',
                '--setenv=WAYNERGY_CONF_PATH=' + directory,
                binary, '-c', '127.0.0.1', '-p', str(server.getsockname()[1]),
                '-N', 'cursor-check', '-E', '-n', '-L', 'info')
            conn, _ = server.accept()
            with conn:
                conn.settimeout(10)
                send(conn, b'Deskflow' + struct.pack('!HH', 1, 8))
                size, = struct.unpack('!I', receive(conn, 4))
                assert size < 1024
                assert receive(conn, size).startswith(b'Deskflow\0\1\0\10')
                visibility(False)
                if args.render:
                    rendered_visibility(True, 1)
                for sequence in (1, 2):
                    exited = time.monotonic()
                    send(conn, b'COUT')
                    visibility(True)
                    if args.render:
                        rendered_visibility(False, 0.2, exited)
                    print('PASS: COUT hides the compositor cursor', flush=True)
                    entered = time.monotonic()
                    send(conn, b'CINN' + struct.pack('!hhIH', 100, 100, sequence, 0))
                    visibility(False)
                    assert json.loads(run('hyprctl', '-j', 'getoption', 'cursor:inactive_timeout'))['float'] == original_timeout
                    if args.render:
                        rendered_visibility(True, 0.2, entered)
                    print('PASS: CINN restores the compositor cursor', flush=True)
                exited = time.monotonic()
                send(conn, b'COUT')
                visibility(True)
                if args.render:
                    rendered_visibility(False, 0.2, exited)
                killed = time.monotonic()
                run('systemctl', '--user', 'kill', '--kill-whom=main', '--signal=KILL', unit)
                visibility(False)
                assert json.loads(run('hyprctl', '-j', 'getoption', 'cursor:inactive_timeout'))['float'] == original_timeout
                if args.render:
                    rendered_visibility(True, 0.2, killed)
                assert json.loads(run('hyprctl', '-j', 'cursorpos')) == original_position, 'cursor helper changed position'
                print('PASS: process failure restores the compositor cursor', flush=True)
        except Exception:
            print(run('journalctl', '--user', '-u', unit, '--no-pager', '-n', '40'), file=sys.stderr)
            raise
        finally:
            subprocess.run(['systemctl', '--user', 'stop', unit], capture_output=True)
            subprocess.run(['systemctl', '--user', 'reset-failed', unit], capture_output=True)
            try:
                subprocess.run([helper, 'show'], check=True)
                if original:
                    subprocess.run([helper, 'hide'], check=True)
            finally:
                if resume_live:
                    run('systemctl', '--user', 'start', 'waynergy.service')
