#!/usr/bin/env python3
"""Native build guard. No network, credentials access, signing or uploads."""
import argparse
import base64
import os
import json
from pathlib import Path


def validate(flavor, encoded, root, mode='debug'):
    mode = mode.lower()
    if mode not in ('debug', 'profile', 'release'):
        raise ValueError('Explicit debug/profile/release build mode is required')
    values = {}
    for item in filter(None, encoded.split(',')):
        decoded = base64.b64decode(item, validate=True).decode()
        key, separator, value = decoded.partition('=')
        if not separator or key in values:
            raise ValueError('Malformed or duplicate Dart define')
        values[key] = value
    if mode != 'debug' and (flavor != 'staging' or values.get('APP_ENV') != 'staging'):
        raise ValueError('Release/profile require the staging flavor and real Firebase config; emulators are debug-only')
    flavor = flavor or 'emulator'
    if flavor not in ('emulator', 'staging'):
        raise ValueError('Only emulator and staging builds are supported')
    if values.get('APP_ENV', flavor) != flavor:
        raise ValueError('APP_ENV must match native flavor')
    if flavor == 'emulator':
        if values.get('FIREBASE_PROJECT_ID', 'demo-rally4ever') != 'demo-rally4ever':
            raise ValueError('Emulator build cannot contain a real Firebase project')
        for key in values:
            if key.startswith(('FIREBASE_', 'STAGING_', 'GOOGLE_')) and key not in (
                'FIREBASE_PROJECT_ID', 'FIREBASE_EMULATOR_HOST',
            ):
                raise ValueError('Real Firebase client config is forbidden in emulator artifacts')
        for directory, name in [('ios/Runner', 'GoogleService-Info.plist'),
                                ('android/app/src', 'google-services.json')]:
            if any((root / directory).rglob(name)):
                raise ValueError('Keep real native Firebase config outside emulator resources')
    else:
        for key in ('USE_FIREBASE_EMULATORS', 'LAN_TESTING'):
            if values.get(key, 'false').lower() != 'false':
                raise ValueError('Staging cannot enable emulators or LAN')
        if values.get('LAN_HOST') or values.get('FIREBASE_EMULATOR_HOST'):
            raise ValueError('Staging cannot contain an emulator host')
        # Owner supplied this candidate; data classification remains a manual release gate.
        if values.get('STAGING_PROJECT_ID') != 'rally4ever-3adaf' or values.get('FIREBASE_PROJECT_ID') != 'rally4ever-3adaf':
            raise ValueError('Only the owner-specified staging candidate is allowed')
        for key in ('FIREBASE_API_KEY', 'FIREBASE_APP_ID', 'FIREBASE_MESSAGING_SENDER_ID'):
            if not values.get(key, '').strip() or any(marker in values[key].upper() for marker in ('REPLACE', 'PLACEHOLDER', 'YOUR_')):
                raise ValueError('Registered platform-specific staging Firebase config is required')
    if mode != 'debug':
        # Real (profile/release) builds must ship the real brand fonts, not
        # silently fall back to the platform default -- debug/test builds
        # are exempt so tests keep running even before the font files exist.
        required = [
            'assets/fonts/Jellee_1223/TTF/Jellee-Bold.ttf',
            'assets/fonts/Inter.ttf',
        ]
        missing = [path for path in required if not (root / path).is_file()]
        if missing:
            raise ValueError(
                'Missing brand font file(s) for a non-debug build: '
                + ', '.join(missing)
                + ' -- supply them (see pubspec.yaml) before building release/profile'
            )
    return flavor


if __name__ == '__main__':
    parser = argparse.ArgumentParser()
    parser.add_argument('--flavor', default=os.environ.get('CONFIGURATION', '').partition('-')[2])
    parser.add_argument('--dart-defines', default=os.environ.get('DART_DEFINES', ''))
    parser.add_argument('--mode', default=os.environ.get('CONFIGURATION', '').partition('-')[0] or os.environ.get('FLUTTER_BUILD_MODE', ''))
    parser.add_argument('--config-file', type=Path)
    args = parser.parse_args()
    try:
        encoded = args.dart_defines
        if args.config_file:
            if encoded:
                raise ValueError('Supply config-file or Dart defines, not both')
            values = json.loads(args.config_file.read_text())
            if not isinstance(values, dict) or not all(isinstance(k, str) and isinstance(v, (str, bool, int)) for k, v in values.items()):
                raise ValueError('Firebase config must be a JSON object of scalar Dart defines')
            encoded = ','.join(base64.b64encode(f'{k}={str(v).lower() if isinstance(v, bool) else v}'.encode()).decode() for k, v in values.items())
        selected = validate(args.flavor, encoded, Path(__file__).resolve().parent.parent, args.mode)
        print(f'Validated {selected} backend isolation (no network access)')
    except Exception as error:
        raise SystemExit(f'Build refused: {error}')
