#!/usr/bin/env python3
"""Exercise a built client over TCP in an active Wayland session.

Usage: python3 test/protocol-handshake.py /path/to/waynergy
Uses isolated configuration and loopback; sends no input or lock events.
"""
import os
from contextlib import contextmanager
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


def frame(body):
    return struct.pack('!I', len(body)) + body


def receive_frame(sock):
    header = receive(sock, 4)
    assert len(header) == 4, 'missing frame header'
    size, = struct.unpack('!I', header)
    assert size < 1024, 'unexpected frame length'
    body = receive(sock, size)
    assert len(body) == size, 'incomplete frame'
    return body


@contextmanager
def client(binary, config, *options):
    with socket.socket() as server, tempfile.TemporaryFile() as log:
        server.bind(('127.0.0.1', 0))
        server.listen(1)
        server.settimeout(5)
        env = dict(os.environ, WAYNERGY_CONF_PATH=str(config))
        proc = subprocess.Popen(
            [binary, '-c', '127.0.0.1', '-p', str(server.getsockname()[1]),
             '-N', 'handshake-check', '-E', '-n', *options],
            env=env, stdout=log, stderr=log)
        try:
            yield server, proc, log
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


def negotiate(conn, name, major, minor):
    conn.sendall(frame(name.encode() + struct.pack('!HH', major, minor)))
    reply = receive_frame(conn)
    expected = name.encode() + struct.pack('!HH', 1, min(minor, 8))
    assert reply.startswith(expected), 'wrong negotiated version'


def check(binary, config, name, major, minor):
    accepted = major == 1 and minor >= 6
    with client(binary, config, '--fatal-ebad') as (server, proc, log):
        conn, _ = server.accept()
        with conn:
            conn.settimeout(15)
            if accepted:
                negotiate(conn, name, major, minor)
            else:
                conn.sendall(frame(name.encode() + struct.pack('!HH', major, minor)))
                assert receive(conn, 4) == b'', 'unsupported version received a reply'
                assert proc.wait(timeout=5) != 0, 'unsupported version was accepted'
                log.seek(0)
                assert b'Unsupported server protocol' in log.read()
    print(f'PASS: {name} {major}.{minor}: ' + ('negotiated' if accepted else 'rejected'))


def check_reconnect(binary, config):
    with client(binary, config) as (server, _, log):
        conn, _ = server.accept()
        with conn:
            conn.settimeout(15)
            negotiate(conn, 'Deskflow', 1, 8)
            conn.sendall(frame(b'CINN' + struct.pack('!hhIH', 0, 0, 7, 0)))
            assert receive_frame(conn) == b'CNOP'
            conn.sendall(frame(b'COUT'))
            assert receive_frame(conn) == b'CNOP'
            log.seek(0)
            output = log.read()
            assert b'screen-enter-ok' in output and b'screen-exit-ok' in output
            assert b'failed with code' not in output, 'screen hooks did not reap their commands'

            # A complete frame and the start of the next can arrive together.
            conn.sendall(frame(b'CALV') + frame(b'QINF')[:3])
            assert receive_frame(conn) == b'CALV'
            assert receive_frame(conn) == b'CNOP'
            conn.sendall(frame(b'QINF')[3:])
            assert receive_frame(conn).startswith(b'DINF')

            # Timeout with a partial header while the peer keeps TCP open.
            conn.sendall(frame(b'CALV')[:3])
            assert receive(conn, 1) == b'', 'idle TCP connection stayed open'
        conn, _ = server.accept()
        with conn:
            conn.settimeout(5)
            negotiate(conn, 'Deskflow', 1, 6)
    print('PASS: screen hooks, split frames and clean reconnect after a partial frame times out')


def check_fatal_timeout(binary, config):
    with client(binary, config, '--fatal-timeout') as (server, proc, _):
        conn, _ = server.accept()
        with conn:
            conn.settimeout(5)
            negotiate(conn, 'Deskflow', 1, 8)
            assert proc.wait(timeout=15) != 0, 'idle timeout was not treated as fatal'
    print('PASS: --fatal-timeout exits after the transport idles')


def check_fatal_bye(binary, config):
    with client(binary, config, '--fatal-none') as (server, proc, _):
        conn, _ = server.accept()
        with conn:
            conn.settimeout(5)
            negotiate(conn, 'Deskflow', 1, 8)
            conn.sendall(frame(b'CBYE'))
            assert proc.wait(timeout=5) != 0, 'orderly disconnect was not treated as fatal'
    print('PASS: --fatal-none exits on CBYE')


if __name__ == '__main__':
    binary = str(Path(sys.argv[1]).resolve())
    with tempfile.TemporaryDirectory(prefix='waynergy-handshake-') as directory:
        config = Path(directory)
        (config / 'config.ini').write_text(
            '[idle-inhibit]\nenable=false\n[screen]\n'
            'enter=echo screen-enter-ok\nexit=echo screen-exit-ok\n')
        for name in ('Synergy', 'Barrier', 'Deskflow'):
            for major, minor in ((1, 0), (1, 5), (1, 6), (1, 7), (1, 8), (1, 9), (2, 0)):
                check(binary, config, name, major, minor)
        check_reconnect(binary, config)
        check_fatal_timeout(binary, config)
        check_fatal_bye(binary, config)
