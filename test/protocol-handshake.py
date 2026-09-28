#!/usr/bin/env python3
"""Exercise a built client over TCP in an active Wayland session.

Usage: python3 test/protocol-handshake.py /path/to/waynergy
Uses isolated configuration and loopback; sends no input or lock events.
"""
import os
from pathlib import Path
import socket
import struct
import subprocess
import sys
import tempfile


def receive(sock, count):
    data = b''
    while len(data) < count:
        chunk = sock.recv(count - len(data))
        if not chunk:
            break
        data += chunk
    return data


def check(binary, config, name, major, minor):
    accepted = major == 1 and minor >= 6
    with socket.socket() as server, tempfile.TemporaryFile() as log:
        server.bind(('127.0.0.1', 0))
        server.listen(1)
        server.settimeout(5)
        env = dict(os.environ, WAYNERGY_CONF_PATH=str(config))
        proc = subprocess.Popen(
            [binary, '-c', '127.0.0.1', '-p', str(server.getsockname()[1]),
             '-N', 'handshake-check', '-E', '-n', '--fatal-ebad'],
            env=env, stdout=log, stderr=log)
        try:
            conn, _ = server.accept()
            with conn:
                conn.settimeout(15)
                hello = name.encode() + struct.pack('!HH', major, minor)
                conn.sendall(struct.pack('!I', len(hello)) + hello)
                header = receive(conn, 4)
                if accepted:
                    assert len(header) == 4, 'missing hello reply'
                    size, = struct.unpack('!I', header)
                    assert size < 1024, 'unexpected hello length'
                    body = receive(conn, size)
                    expected = name.encode() + struct.pack('!HH', 1, min(minor, 8))
                    assert body.startswith(expected), 'wrong negotiated version'
                else:
                    assert header == b'', 'unsupported version received a reply'
                    assert proc.wait(timeout=5) != 0, 'unsupported version was accepted'
                    log.seek(0)
                    assert b'Unsupported server protocol' in log.read()
        except Exception:
            log.seek(0)
            print(log.read().decode(errors='replace'), file=sys.stderr)
            raise
        finally:
            if proc.poll() is None:
                proc.terminate()
                try:
                    proc.wait(timeout=5)
                except subprocess.TimeoutExpired:
                    proc.kill()
                    proc.wait()
    print(f'PASS: {name} {major}.{minor}: ' + ('negotiated' if accepted else 'rejected'))


if __name__ == '__main__':
    binary = str(Path(sys.argv[1]).resolve())
    with tempfile.TemporaryDirectory(prefix='waynergy-handshake-') as directory:
        config = Path(directory)
        (config / 'config.ini').write_text('[idle-inhibit]\nenable=false\n')
        for name in ('Synergy', 'Barrier', 'Deskflow'):
            for major, minor in ((1, 0), (1, 5), (1, 6), (1, 7), (1, 8), (1, 9), (2, 0)):
                check(binary, config, name, major, minor)
