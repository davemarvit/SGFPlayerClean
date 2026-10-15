#!/usr/bin/env python3
"""Exercise production Swift transport against a localhost-only WebSocket fixture."""
import base64
import argparse
import hashlib
from pathlib import Path
import socket
import struct
import subprocess
import tempfile
import threading


def exact(conn, count):
    data = b""
    while len(data) < count:
        chunk = conn.recv(count - len(data))
        if not chunk:
            raise EOFError("socket closed")
        data += chunk
    return data


def read_frame(conn):
    first, second = exact(conn, 2)
    length = second & 127
    if length == 126:
        length = struct.unpack("!H", exact(conn, 2))[0]
    elif length == 127:
        length = struct.unpack("!Q", exact(conn, 8))[0]
    mask = exact(conn, 4) if second & 128 else None
    payload = exact(conn, length)
    if mask:
        payload = bytes(c ^ mask[i % 4] for i, c in enumerate(payload))
    return first & 15, payload


def frame(conn, opcode, payload):
    assert len(payload) < 126
    conn.sendall(bytes([128 | opcode, len(payload)]) + payload)


def serve(listener, failures):
    try:
        for attempt in (1, 2):
            conn, _ = listener.accept()
            with conn:
                conn.settimeout(20)
                request = b""
                while not request.endswith(b"\r\n\r\n"):
                    request += exact(conn, 1)
                headers = dict(line.split(":", 1) for line in request.decode().split("\r\n")[1:] if ":" in line)
                key = next(value.strip() for name, value in headers.items() if name.lower() == "sec-websocket-key")
                accept = base64.b64encode(hashlib.sha1((key + "258EAFA5-E914-47DA-95CA-C5AB0DC85B11").encode()).digest()).decode()
                conn.sendall(("HTTP/1.1 101 Switching Protocols\r\nUpgrade: websocket\r\n"
                              "Connection: Upgrade\r\nSec-WebSocket-Accept: " + accept + "\r\n\r\n").encode())
                frame(conn, 1, f"text-{attempt}".encode())
                frame(conn, 2, f"binary-{attempt}".encode())
                opcode, payload = read_frame(conn)
                assert (opcode, payload) == (1, b"client-command")
                if attempt == 1:
                    # Abrupt loss must restart the production receive loop on a new socket.
                    conn.shutdown(socket.SHUT_RDWR)
                    continue
                opcode, payload = read_frame(conn)
                assert opcode == 9, f"Expected WebSocket ping, got {opcode}"
                frame(conn, 10, payload)
                frame(conn, 1, b"pong-observed")
                try:
                    opcode, payload = read_frame(conn)
                    if opcode == 8:
                        frame(conn, 8, payload)
                except (EOFError, OSError):
                    pass
    except Exception as error:
        failures.append(repr(error))


def main():
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument('--ogs-review', action='store_true', help='Use the review-specific ephemeral WebSocket session.')
    args = parser.parse_args()
    root = Path(__file__).resolve().parents[2]
    networking = root / "SGFPlayerClean/Services/Networking"
    with tempfile.TemporaryDirectory(prefix="sgfplayer-loopback-") as temp:
        executable = Path(temp) / "probe"
        flags = ['-D', 'SGF_OGS_REVIEW'] if args.ogs_review else []
        subprocess.run(["swiftc", *flags, str(networking / "OGSConnectionController.swift"),
                        str(networking / "OGSURLSessionSocket.swift"),
                        str(Path(__file__).with_name("main.swift")), "-o", str(executable)], check=True)
        with socket.socket() as listener:
            listener.bind(("127.0.0.1", 0))
            listener.listen()
            listener.settimeout(25)
            failures = []
            thread = threading.Thread(target=serve, args=(listener, failures), daemon=True)
            thread.start()
            result = subprocess.run([str(executable), f"ws://127.0.0.1:{listener.getsockname()[1]}/"], timeout=30)
            thread.join(timeout=1)
            if result.returncode or failures or thread.is_alive():
                raise SystemExit(f"Loopback failure: status={result.returncode}, server={failures}")


if __name__ == "__main__":
    main()
