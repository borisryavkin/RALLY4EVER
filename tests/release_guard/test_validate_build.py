import base64
import importlib.util
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
