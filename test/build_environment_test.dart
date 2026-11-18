import 'package:flutter_test/flutter_test.dart';
import 'package:rally4ever/data/build_environment.dart';

void main() {
  test('emulator is default and refuses real config', () {
    expect(BuildEnvironment.validate(), 'emulator');
    expect(
      () => BuildEnvironment.validate(project: 'rally4ever-3adaf'),
      throwsStateError,
    );
    expect(
      () => BuildEnvironment.validate(apiKey: 'real-config'),
      throwsStateError,
    );
    expect(
      () => BuildEnvironment.validate(firebaseAppId: 'real-app'),
      throwsStateError,
    );
  });
  test('non-debug never falls back to emulator', () {
    expect(() => BuildEnvironment.validate(debug: false), throwsStateError);
    expect(
      () => BuildEnvironment.validate(debug: false, nativeFlavor: 'emulator'),
      throwsStateError,
    );
    expect(
      BuildEnvironment.validate(
        debug: false,
        nativeFlavor: 'staging',
        project: 'rally4ever-3adaf',
        approvedStagingProject: 'rally4ever-3adaf',
      ),
      'staging',
    );
  });
  test(
    'staging requires explicit matching project and refuses emulator flags',
    () {
      String validate({
        bool emulators = false,
        bool lan = false,
        String host = '',
      }) => BuildEnvironment.validate(
        nativeFlavor: 'staging',
        project: 'rally4ever-3adaf',
        approvedStagingProject: 'rally4ever-3adaf',
        emulators: emulators,
        lan: lan,
        emulatorHost: host,
      );
      expect(validate(), 'staging');
      expect(() => validate(emulators: true), throwsStateError);
      expect(() => validate(lan: true), throwsStateError);
      expect(() => validate(host: '127.0.0.1'), throwsStateError);
      expect(
        () => BuildEnvironment.validate(nativeFlavor: 'staging'),
        throwsStateError,
      );
      expect(
        () => BuildEnvironment.validate(
          nativeFlavor: 'staging',
          project: 'wrong',
          approvedStagingProject: 'rally4ever-3adaf',
        ),
        throwsStateError,
      );
      expect(
        () => BuildEnvironment.validate(
          nativeFlavor: 'staging',
          flavor: 'emulator',
        ),
        throwsStateError,
      );
      expect(
        () => BuildEnvironment.validate(nativeFlavor: 'production'),
        throwsStateError,
      );
    },
  );
}
