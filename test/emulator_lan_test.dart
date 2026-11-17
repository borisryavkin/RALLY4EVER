import 'package:flutter_test/flutter_test.dart';
import 'package:rally4ever/data/emulator_backend.dart';
import 'package:rally4ever/data/emulator_settings.dart';

void main() {
  test('default stays loopback and private LAN hosts require both explicit settings', () {
    expect(EmulatorSettings.resolve().host, '127.0.0.1');
    expect(EmulatorSettings.resolve().lanTesting, false);
    for (final host in [
      '10.1.2.3',
      '172.16.0.1',
      '172.31.255.254',
      '192.168.1.50',
    ]) {
      expect(() => EmulatorSettings.resolve(host: host), throwsArgumentError);
      final settings = EmulatorSettings.resolve(
        lanTesting: true,
        lanHost: host,
      );
      expect(settings.host, host);
      expect(settings.webOrigin, 'http://$host:57602');
    }
    expect(
      () => EmulatorSettings.resolve(lanHost: '192.168.1.50'),
      throwsStateError,
    );
    expect(
      () => EmulatorSettings.resolve(lanTesting: true),
      throwsArgumentError,
    );
    expect(
      () => EmulatorSettings.resolve(
        lanTesting: true,
        lanHost: '192.168.1.50',
        host: '192.168.1.51',
      ),
      throwsArgumentError,
    );
  });
  test('public, malformed, non-RFC1918 and wildcard hosts stay forbidden in LAN mode', () {
    for (final host in [
      '8.8.8.8',
      '172.15.0.1',
      '172.32.0.1',
      '192.169.1.1',
      '169.254.1.1',
      '100.64.0.1',
      '127.0.0.1',
      '0.0.0.0',
      '::1',
      'fc00::1',
      'firebase.google.com',
      '192.168.1.50:9099',
      '192.168.001.50',
      '10.0.0.256',
      'http://10.1.2.3',
      '10.1.2.3/24',
    ]) {
      expect(
        () => EmulatorSettings.resolve(lanTesting: true, lanHost: host),
        throwsArgumentError,
        reason: host,
      );
    }
  });
  test('LAN is blocked in release/profile and every non-demo project is refused before initialization', () async {
    expect(
      () => EmulatorSettings.resolve(
        lanTesting: true,
        lanHost: '192.168.1.50',
        debugMode: false,
      ),
      throwsStateError,
    );
    for (final project in [
      'production-rally4ever',
      'rally4ever-staging',
      'demo-other',
    ]) {
      expect(
        () => EmulatorSettings.resolve(requestedProjectId: project),
        throwsArgumentError,
      );
      await expectLater(
        EmulatorBackend.connect(
          enabled: true,
          lanTesting: true,
          lanHost: '192.168.1.50',
          requestedProjectId: project,
        ),
        throwsArgumentError,
      );
    }
  });
}
