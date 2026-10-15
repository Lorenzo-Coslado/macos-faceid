"""Client de test : simule ce que fait le module PAM.

Usage :  python -m faceid.verify_client [--lock]
Sortie 0 si "OK", 1 si "FAIL", 2 si erreur/daemon injoignable.
"""
import sys
import socket

from . import config


def command_for_args(args):
    return b"VERIFY_LOCK\n" if "--lock" in args else b"VERIFY\n"


def main():
    lock_mode = "--lock" in sys.argv[1:]
    s = socket.socket(socket.AF_UNIX, socket.SOCK_STREAM)
    s.settimeout((config.LOCK_TIMEOUT_S if lock_mode else config.VERIFY_TIMEOUT_S) + 1)
    try:
        s.connect(str(config.SOCKET_PATH))
        s.sendall(command_for_args(sys.argv[1:]))
        reply = s.recv(32).decode("ascii", "ignore").strip()
    except OSError as e:
        print(f"ERR {e}", file=sys.stderr)
        return 2
    finally:
        s.close()
    print(reply)
    return 0 if reply == "OK" else 1


if __name__ == "__main__":
    raise SystemExit(main())
