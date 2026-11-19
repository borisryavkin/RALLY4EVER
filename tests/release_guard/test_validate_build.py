import base64
import importlib.util
import json
import os
import shutil
import subprocess
import tempfile
import unittest
from pathlib import Path

spec = importlib.util.spec_from_file_location('guard', Path(__file__).resolve().parents[2] / 'scripts/validate-build.py')
guard = importlib.util.module_from_spec(spec)
spec.loader.exec_module(guard)


def encode(values):
    return ','.join(base64.b64encode(f'{k}={v}'.encode()).decode() for k, v in values.items())


class BuildGuardTests(unittest.TestCase):
    def setUp(self):
        self.temp = tempfile.TemporaryDirectory()
        self.addCleanup(self.temp.cleanup)
        self.root = Path(self.temp.name)
        self.config = dict(APP_ENV='staging', STAGING_PROJECT_ID='rally4ever-3adaf',
                           FIREBASE_PROJECT_ID='rally4ever-3adaf', FIREBASE_API_KEY='fixture',
                           FIREBASE_APP_ID='fixture', FIREBASE_MESSAGING_SENDER_ID='fixture')
        # validate() requires the real brand fonts to exist for non-debug
        # builds; stub presence only (content is irrelevant to that check).
        for font in ('assets/fonts/Jellee_1223/TTF/Jellee-Bold.ttf', 'assets/fonts/Inter.ttf'):
            path = self.root / font
            path.parent.mkdir(parents=True, exist_ok=True)
            path.write_bytes(b'')

    def test_demo_only_artifacts(self):
        self.assertEqual(guard.validate('emulator', encode(dict(USE_FIREBASE_EMULATORS='true')), self.root), 'emulator')
        for values in [dict(FIREBASE_PROJECT_ID='real-project'), dict(FIREBASE_API_KEY='real'), dict(STAGING_PROJECT_ID='real')]:
            with self.assertRaises(ValueError):
                guard.validate('emulator', encode(values), self.root)
        path = self.root / 'ios/Runner/GoogleService-Info.plist'
        path.parent.mkdir(parents=True)
        path.write_text('real client configuration')
        with self.assertRaises(ValueError):
            guard.validate('emulator', '', self.root)

    def test_staging_does_not_accept_emulator_configuration(self):
        self.assertEqual(guard.validate('staging', encode(self.config), self.root), 'staging')
        for key, value in [('USE_FIREBASE_EMULATORS', 'true'), ('LAN_TESTING', 'true'), ('LAN_HOST', '192.168.1.1'), ('FIREBASE_PROJECT_ID', 'other'), ('FIREBASE_API_KEY', 'REPLACE_ME')]:
            with self.assertRaises(ValueError):
                guard.validate('staging', encode({**self.config, key: value}), self.root)
        with self.assertRaises(ValueError):
            guard.validate('staging', '', self.root)

    def test_mixed_or_unknown_flavors_fail(self):
        with self.assertRaises(ValueError):
            guard.validate('production', '', self.root)
        with self.assertRaises(ValueError):
            guard.validate('emulator', encode(self.config), self.root)


    def test_release_and_profile_require_real_config(self):
        for mode in ('release', 'profile'):
            for flavor in ('', 'emulator', 'staging'):
                with self.subTest(mode=mode, flavor=flavor):
                    with self.assertRaises(ValueError):
                        guard.validate(flavor, '', self.root, mode)
            self.assertEqual(guard.validate('staging', encode(self.config), self.root, mode), 'staging')
            for key in self.config:
                incomplete = {k: v for k, v in self.config.items() if k != key}
                with self.subTest(mode=mode, missing=key), self.assertRaises(ValueError):
                    guard.validate('staging', encode(incomplete), self.root, mode)
            with self.assertRaises(ValueError):
                guard.validate('emulator', encode({'USE_FIREBASE_EMULATORS': 'true'}), self.root, mode)

    def test_missing_brand_fonts_fail_release_profile_but_not_debug(self):
        (self.root / 'assets/fonts/Inter.ttf').unlink()
        for mode in ('release', 'profile'):
            with self.subTest(mode=mode):
                with self.assertRaises(ValueError) as cm:
                    guard.validate('staging', encode(self.config), self.root, mode)
                self.assertIn('Missing brand font file', str(cm.exception))
                self.assertIn('Inter.ttf', str(cm.exception))
        # debug never needs the real fonts -- the platform default is fine
        # so tests keep running even without them.
        self.assertEqual(
            guard.validate('emulator', encode(dict(USE_FIREBASE_EMULATORS='true')), self.root, 'debug'),
            'emulator',
        )

    def test_xcode_and_gradle_wiring(self):
        root = Path(__file__).resolve().parents[2]
        project = (root / 'ios/Runner.xcodeproj/project.pbxproj').read_text()
        phases = project.split('97C146ED1CF9000F007C117D /* Runner */ = {')[1].split('buildRules')[0]
        self.assertLess(phases.index('Validate Backend Flavor'), phases.index('Run Script'))
        self.assertIn('alwaysOutOfDate = 1', project.split('D6E2C3AACD40C90A23D4C4B2 /* Validate Backend Flavor */ = {')[1].split('};')[0])
        gradle = (root / 'android/app/build.gradle.kts').read_text()
        self.assertIn('"--mode", variant.buildType', gradle)
        self.assertIn('dependsOn(guard)', gradle)
        env = {**os.environ, 'CONFIGURATION': 'Release', 'FLUTTER_BUILD_MODE': 'debug', 'DART_DEFINES': ''}
        result = subprocess.run(['python3', str(root / 'scripts/validate-build.py')], env=env, capture_output=True, text=True)
        self.assertNotEqual(result.returncode, 0)
        self.assertIn('Release/profile require', result.stderr)

    def test_dart_compiler_rejects_missing_config_outside_debug(self):
        root = Path(__file__).resolve().parents[2]
        dart = shutil.which('dart')
        self.assertIsNotNone(dart, 'Dart SDK required to verify compile-time guard')
        probe = self.root / 'probe.dart'
        guard_uri = (root / 'lib/data/build_configuration_guard.dart').as_uri()
        probe.write_text(f"import '{guard_uri}';\nvoid main() {{ backendBuildConfiguration; }}\n")
        for mode in ('product', 'profile'):
            for values, success in (({}, False), (self.config, True),
                                    ({**self.config, 'USE_FIREBASE_EMULATORS': 'true'}, False)):
                command = [dart, 'compile', 'kernel', f'-Ddart.vm.{mode}=true']
                command += [f'-D{k}={v}' for k, v in values.items()]
                command += [str(probe), '-o', str(self.root / 'probe.dill')]
                result = subprocess.run(command, capture_output=True, text=True)
                with self.subTest(mode=mode, config=bool(values), success=success):
                    self.assertEqual(result.returncode == 0, success, result.stdout + result.stderr)
                    if not success:
                        self.assertIn('Release/profile builds require', result.stdout + result.stderr)

    def test_staging_scripts_fail_before_flutter_on_missing_config(self):
        root = Path(__file__).resolve().parents[2]
        for platform in ('ios', 'android'):
            result = subprocess.run([str(root / f'scripts/build-{platform}-staging.sh'),
                '--build-number', '14', '--config', str(self.root / 'missing.json'), '--check-only'],
                capture_output=True, text=True)
            self.assertNotEqual(result.returncode, 0)
            self.assertIn('Build refused', result.stdout + result.stderr)

    def test_staging_scripts_always_forward_config_flavor_and_mode(self):
        root = Path(__file__).resolve().parents[2]
        config = self.root / 'config.json'
        config.write_text(json.dumps(self.config))
        capture = self.root / 'args.json'
        stub = self.root / 'flutter'
        stub.write_text('#!/usr/bin/env python3\nimport json, os, sys\nfrom pathlib import Path\nPath(os.environ["BUILD_ARGS_CAPTURE"]).write_text(json.dumps(sys.argv[1:]))\n')
        stub.chmod(0o755)
        for platform, mode, target in (('ios', 'release', 'ipa'), ('ios', 'profile', 'ios'),
                                       ('android', 'release', 'appbundle'), ('android', 'profile', 'appbundle')):
            result = subprocess.run([str(root / f'scripts/build-{platform}-staging.sh'),
                '--build-number', '14', '--mode', mode, '--config', str(config)],
                env={**os.environ, 'FLUTTER_BIN': str(stub), 'BUILD_ARGS_CAPTURE': str(capture)},
                capture_output=True, text=True)
            with self.subTest(platform=platform, mode=mode):
                self.assertEqual(result.returncode, 0, result.stderr)
                args = json.loads(capture.read_text())
                self.assertEqual(args[:3], ['build', target, f'--{mode}'])
                self.assertEqual(args[3:5], ['--flavor', 'staging'])
                self.assertIn(f'--dart-define-from-file={config.resolve()}', args)
                self.assertIn('--build-number=14', args)
                if target == 'ipa':
                    self.assertIn('--export-options-plist=ios/ExportOptions.plist', args)

    def test_ios_location_usage_descriptions_do_not_enable_background_tracking(self):
        import plistlib
        root = Path(__file__).resolve().parents[2]
        values = plistlib.loads((root / 'ios/Runner/Info.plist').read_bytes())
        for key in ('NSLocationWhenInUseUsageDescription', 'NSLocationAlwaysAndWhenInUseUsageDescription'):
            self.assertTrue(values.get(key, '').strip(), key)
        self.assertNotIn('location', values.get('UIBackgroundModes', []))
