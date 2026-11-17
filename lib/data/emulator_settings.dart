import 'package:flutter/foundation.dart';

/// Demo-only development transport. This never enables a production project.
class EmulatorSettings {
  const EmulatorSettings._(this.host, this.lanTesting);
  static const projectId = 'demo-rally4ever';
  final String host;
  final bool lanTesting;
  String get webOrigin =>
      lanTesting ? 'http://$host:57602' : 'http://localhost:7357';

  static bool isPrivateIPv4(String host) {
    final parts = host.split('.');
    if (parts.length != 4) return false;
    final octets = <int>[];
    for (final part in parts) {
      final value = int.tryParse(part);
      if (value == null || value < 0 || value > 255 || '$value' != part) {
        return false;
      }
      octets.add(value);
    }
    return octets[0] == 10 ||
        (octets[0] == 172 && octets[1] >= 16 && octets[1] <= 31) ||
        (octets[0] == 192 && octets[1] == 168);
  }

  factory EmulatorSettings.resolve({
    String host = '',
    String requestedProjectId = projectId,
    bool lanTesting = false,
    String lanHost = '',
    bool debugMode = kDebugMode,
  }) {
    if (requestedProjectId != projectId) {
      throw ArgumentError.value(
        requestedProjectId,
        'projectId',
        'Only demo-rally4ever is allowed',
      );
    }
    if (lanTesting) {
      if (!debugMode) {
        throw StateError('LAN testing is development-only (debug builds)');
      }
      if (!isPrivateIPv4(lanHost)) {
        throw ArgumentError.value(
          lanHost,
          'LAN_HOST',
          'Supply the Mac’s private IPv4 address',
        );
      }
      if (host.isNotEmpty && host != lanHost) {
        throw ArgumentError.value(
          host,
          'host',
          'Host must match the explicit LAN_HOST',
        );
      }
      return EmulatorSettings._(lanHost, true);
    }
    if (lanHost.isNotEmpty) {
      throw StateError('LAN_HOST requires LAN_TESTING=true');
    }
    final resolved = host.isEmpty ? '127.0.0.1' : host;
    if (!const ['localhost', '127.0.0.1', '10.0.2.2'].contains(resolved)) {
      throw ArgumentError.value(
        resolved,
        'host',
        'Only local emulator hosts are allowed without LAN opt-in',
      );
    }
    return EmulatorSettings._(resolved, false);
  }
}
