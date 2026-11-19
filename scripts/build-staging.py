#!/usr/bin/env python3
"""Validate staging settings, then build locally. Never signs in or uploads."""
import argparse
import os
from pathlib import Path
import subprocess
import sys


def main():
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument('--platform', required=True, choices=('ios', 'android'))
    parser.add_argument('--mode', choices=('release', 'profile'), default='release')
    parser.add_argument('--build-number', type=int, required=True)
    parser.add_argument('--build-name', default='1.0.3')
    parser.add_argument('--config', type=Path)
    parser.add_argument('--export-options', choices=('normal','internal'), default='normal')
    parser.add_argument('--check-only', action='store_true', help='Validate without starting Flutter')
    args = parser.parse_args()
    if args.build_number < 14:
        parser.error('Build 13 is consumed (uploaded); recheck stores and choose 14 or higher')
    root = Path(__file__).resolve().parent.parent
    config = (args.config or root / f'config/staging.{args.platform}.json').resolve()
    # The validator reads JSON itself; config values never appear in commands/logs.
    subprocess.run([
        sys.executable, str(root / 'scripts/validate-build.py'),
        '--flavor', 'staging', '--mode', args.mode, '--dart-defines', '',
        '--config-file', str(config),
    ], cwd=root, check=True)
    if args.check_only:
        return
    target = 'ipa' if args.platform == 'ios' and args.mode == 'release' else (
        'ios' if args.platform == 'ios' else 'appbundle')
    command = [
        os.environ.get('FLUTTER_BIN', 'flutter'), 'build', target,
        f'--{args.mode}', '--flavor', 'staging',
        f'--dart-define-from-file={config}',
        f'--build-name={args.build_name}', f'--build-number={args.build_number}',
    ]
    if target == 'ipa':
        export = 'ios/ExportOptions.plist' if args.export_options == 'normal' else 'ios/ExportOptions.internal.plist'
        command.append(f'--export-options-plist={export}')
    subprocess.run(command, cwd=root, check=True)


if __name__ == '__main__':
    main()
