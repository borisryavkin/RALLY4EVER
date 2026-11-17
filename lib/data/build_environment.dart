import 'package:flutter/services.dart' show appFlavor;

/// Flavor selection fails closed before any Firebase SDK request.
class BuildEnvironment {
  static String validate({
    String? nativeFlavor,
    String flavor = const String.fromEnvironment('APP_ENV'),
    bool emulators = const bool.fromEnvironment('USE_FIREBASE_EMULATORS'),
    bool lan = const bool.fromEnvironment('LAN_TESTING'),
    String lanHost = const String.fromEnvironment('LAN_HOST'),
    String emulatorHost = const String.fromEnvironment(
      'FIREBASE_EMULATOR_HOST',
    ),
    String project = const String.fromEnvironment('FIREBASE_PROJECT_ID'),
    String googleServerClientId = const String.fromEnvironment(
      'GOOGLE_SERVER_CLIENT_ID',
    ),
    String apiKey = const String.fromEnvironment('FIREBASE_API_KEY'),
    String firebaseAppId = const String.fromEnvironment('FIREBASE_APP_ID'),
    String approvedStagingProject = const String.fromEnvironment(
      'STAGING_PROJECT_ID',
    ),
  }) {
    final selected =
        nativeFlavor ?? appFlavor ?? (flavor.isEmpty ? 'emulator' : flavor);
    if (flavor.isNotEmpty && flavor != selected) {
      throw StateError('APP_ENV must match the native build flavor');
    }
    if (selected == 'emulator') {
      if (apiKey.isNotEmpty ||
          firebaseAppId.isNotEmpty ||
          googleServerClientId.isNotEmpty) {
        throw StateError(
          'Emulator builds must not contain real Firebase config',
        );
      }
      if (project.isNotEmpty && project != 'demo-rally4ever') {
        throw StateError('Emulator builds accept only demo-rally4ever');
      }
    } else if (selected == 'staging') {
      if (emulators || lan || lanHost.isNotEmpty || emulatorHost.isNotEmpty) {
        throw StateError('Staging must never enable emulator or LAN settings');
      }
      if (project.isEmpty ||
          project.startsWith('demo-') ||
          approvedStagingProject != 'rally4ever-3adaf' ||
          project != approvedStagingProject) {
        throw StateError(
          'An explicitly approved staging Firebase project is required',
        );
      }
    } else {
      throw StateError('Only emulator and staging flavors are supported');
    }
    return selected;
  }
}
