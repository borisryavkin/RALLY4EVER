// Pure Dart so the same compile-time safety check also covers web builds.
class _BackendBuildConfiguration {
  const _BackendBuildConfiguration(bool valid)
    : assert(
        valid,
        'Release/profile builds require APP_ENV=staging and real Firebase '
        'config for rally4ever-3adaf. Emulator/LAN settings are debug-only. '
        'Use scripts/build-ios-staging.sh or scripts/build-android-staging.sh.',
      );
}

const backendBuildConfiguration = _BackendBuildConfiguration(
  (!bool.fromEnvironment('dart.vm.product') &&
          !bool.fromEnvironment('dart.vm.profile')) ||
      (String.fromEnvironment('APP_ENV') == 'staging' &&
          String.fromEnvironment('STAGING_PROJECT_ID') == 'rally4ever-3adaf' &&
          String.fromEnvironment('FIREBASE_PROJECT_ID') == 'rally4ever-3adaf' &&
          String.fromEnvironment('FIREBASE_API_KEY') != '' &&
          String.fromEnvironment('FIREBASE_APP_ID') != '' &&
          String.fromEnvironment('FIREBASE_MESSAGING_SENDER_ID') != '' &&
          !bool.fromEnvironment('USE_FIREBASE_EMULATORS') &&
          !bool.fromEnvironment('LAN_TESTING') &&
          String.fromEnvironment('LAN_HOST') == '' &&
          String.fromEnvironment('FIREBASE_EMULATOR_HOST') == ''),
);
