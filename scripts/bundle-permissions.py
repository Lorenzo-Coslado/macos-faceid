#!/usr/bin/env python3
"""Check that every user can read an app after Installer makes root its owner."""
import argparse
import os
from pathlib import Path
import stat
import sys


def bundle_paths(app):
    yield app
    for folder, directories, files in os.walk(app, followlinks=False):
        for name in directories + files:
            path = Path(folder) / name
            if not path.is_symlink():
                yield path


def normalize(app):
    if app.resolve().is_relative_to('/Applications'):
        raise ValueError('Normalize a staged bundle, never the installed app')
    for path in bundle_paths(app):
        mode = stat.S_IMODE(path.stat().st_mode)
        public = 0o555 if path.is_dir() or mode & 0o111 else 0o444
        path.chmod((mode & ~0o022) | public)


def check(app):
    failures = []
    for path in bundle_paths(app):
        mode = stat.S_IMODE(path.stat().st_mode)
        expected = 0o005 if path.is_dir() or mode & 0o111 else 0o004
        if mode & expected != expected or mode & 0o022:
            failures.append(f'{path.relative_to(app)}: {mode:04o}')
    if failures:
        raise ValueError('Bundle permissions unsafe after root installation:\n' + '\n'.join(failures[:20]))


def main():
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument('--fix', action='store_true', help='Normalize staged app permissions')
    parser.add_argument('app', type=Path)
    args = parser.parse_args()
    if not (args.app / 'Contents/MacOS/Mugshot').is_file():
        parser.error('Expected Mugshot.app')
    if args.fix:
        normalize(args.app)
    check(args.app)
    print('Bundle permissions: readable and executable by a non-owner')


if __name__ == '__main__':
    try:
        main()
    except (ValueError, OSError) as error:
        print(error, file=sys.stderr)
        sys.exit(1)
