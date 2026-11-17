#!/usr/bin/env python3
"""Native build guard. No network, credentials access, signing or uploads."""
import argparse
import base64
import os
from pathlib import Path


def validate(flavor, encoded, root):
    values = {}
    for item in filter(None, encoded.split(',')):
        decoded = base64.b64decode(item, validate=True).decode()
        key, separator, value = decoded.partition('=')
        if not separator or key in values:
            raise ValueError('Malformed or duplicate Dart define')
        values[key] = value
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
            if not values.get(key) or 'REPLACE' in values[key]:
                raise ValueError('Registered platform-specific staging Firebase config is required')
    return flavor


if __name__ == '__main__':
    parser = argparse.ArgumentParser()
    parser.add_argument('--flavor', default=os.environ.get('CONFIGURATION', '').partition('-')[2])
    parser.add_argument('--dart-defines', default=os.environ.get('DART_DEFINES', ''))
    args = parser.parse_args()
    try:
        selected = validate(args.flavor, args.dart_defines, Path(__file__).resolve().parent.parent)
        print(f'Validated {selected} backend isolation (no network access)')
    except Exception as error:
        raise SystemExit(f'Build refused: {error}')
