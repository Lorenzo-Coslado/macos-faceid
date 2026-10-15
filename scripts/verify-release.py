#!/usr/bin/env python3
"""Validate the actual notarized artifacts, their payload, and release provenance."""
import argparse
import hashlib
import json
from pathlib import Path
import plistlib
import re
import subprocess
import sys
import tempfile

ROOT = Path(__file__).resolve().parents[1]


def run(args):
    result = subprocess.run([str(x) for x in args], text=True, capture_output=True)
    if result.returncode:
        raise ValueError(f'{Path(str(args[0])).name}: {(result.stderr or result.stdout)[-1800:]}')
    return result.stdout + result.stderr


def digest(path):
    with path.open('rb') as file:
        return hashlib.file_digest(file, 'sha256').hexdigest()


def validate(version, build, commit):
    dist = ROOT / 'dist'
    app = dist / 'Mugshot.app'
    info = plistlib.loads((app / 'Contents/Info.plist').read_bytes())
    if (info['CFBundleShortVersionString'], info['CFBundleVersion']) != (version, build):
        raise ValueError('Artifact version/build differs from the requested release')
    run(['codesign', '--verify', '--deep', '--strict', '-R',
         '=anchor apple generic and certificate leaf[field.1.2.840.113635.100.6.1.13] exists', app])
    details = run(['codesign', '-dv', '--verbose=4', app])
    if 'runtime' not in details or 'Timestamp=' not in details:
        raise ValueError('Release app requires hardened runtime and a secure timestamp')
    team = re.search(r'^TeamIdentifier=(.+)$', details, re.M).group(1)
    run([sys.executable, ROOT / 'scripts/bundle-permissions.py', app])
    for artifact, kind in [(app, 'exec'), (dist / 'Mugshot.dmg', 'open'), (dist / 'Mugshot.pkg', 'install')]:
        run(['xcrun', 'stapler', 'validate', artifact])
        args = ['spctl', '-a', '-vv', '-t', kind]
        if kind == 'open':
            args += ['--context', 'context:primary-signature']
        run(args + [artifact])
    pkg = dist / 'Mugshot.pkg'
    signature = run(['pkgutil', '--check-signature', pkg])
    if not re.search(r'Developer ID Installer: .*\(' + re.escape(team) + r'\)', signature):
        raise ValueError('Package must use the same Developer ID team as the app')
    with tempfile.TemporaryDirectory(prefix='mugshot-release-verify-') as folder:
        expanded = Path(folder) / 'package'
        run(['pkgutil', '--expand-full', pkg, expanded])
        payload = expanded / 'app.pkg/Payload/Applications/Mugshot.app'
        run([sys.executable, ROOT / 'scripts/bundle-permissions.py', payload])
        run(['codesign', '--verify', '--deep', '--strict', payload])
        if digest(payload / 'Contents/MacOS/Mugshot') != digest(app / 'Contents/MacOS/Mugshot'):
            raise ValueError('Package contains a different executable')
        metadata = (expanded / 'app.pkg/Scripts/expected-app-sha256').read_text().strip()
        if metadata != digest(app / 'Contents/MacOS/Mugshot'):
            raise ValueError('Installer payload verification metadata is stale')
    return {
        'version': version, 'build': build, 'commit': commit, 'team': team,
        'app_sha256': digest(app / 'Contents/MacOS/Mugshot'),
        'artifacts': {name: digest(dist / name) for name in ['Mugshot.dmg', 'Mugshot.pkg']},
    }


def main():
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument('version')
    parser.add_argument('build')
    parser.add_argument('--record', action='store_true', help='Write the verification manifest after building')
    args = parser.parse_args()
    commit = run(['git', 'rev-parse', 'HEAD']).strip()
    path = ROOT / 'dist/release-manifest.json'
    previous = json.loads(path.read_text()) if path.exists() else None
    current = validate(args.version, args.build, commit)
    if args.record:
        path.write_text(json.dumps(current, indent=2) + '\n')
        hashes = '\n'.join(f'{value}  {name}' for name, value in current['artifacts'].items())
        (ROOT / 'dist/SHA256SUMS').write_text(hashes + '\n')
    elif previous != current:
        raise ValueError('Artifacts or source commit changed since verification; rebuild the release')
    print(f"Release {args.version} ({args.build}): signatures, notarization, Gatekeeper, payload and permissions verified")


if __name__ == '__main__':
    try:
        main()
    except (ValueError, OSError, KeyError) as error:
        print(error, file=sys.stderr)
        sys.exit(1)
