"""Point d'entrée unique du binaire autonome : dispatch selon argv[1]."""
import sys


def main():
    cmd = sys.argv[1] if len(sys.argv) > 1 else "daemon"
    rest = sys.argv[2:]
    if cmd == "daemon":
        from faceid.daemon import main as m
        return m()
    if cmd == "enroll":
        sys.argv = ["enroll"] + rest          # pour que --json soit vu
        from faceid.enroll import main as m
        return m()
    if cmd == "verify":
        from faceid.verify_client import main as m
        return m()
    if cmd == "selftest":
        from faceid.selftest import main as m
        return m()
    sys.stderr.write("usage: faceid {daemon|enroll|verify|selftest}\n")
    return 2


if __name__ == "__main__":
    sys.exit(main())
