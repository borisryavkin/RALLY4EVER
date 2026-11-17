import 'package:flutter/material.dart';
import 'package:timezone/data/latest.dart' as tz;

import 'data/emulator_backend.dart';
import 'data/build_environment.dart';
import 'data/staging_backend.dart';
import 'participant/app.dart';
import 'participant/repository.dart';

void main() async {
  WidgetsFlutterBinding.ensureInitialized();
  tz.initializeTimeZones();
  ParticipantRepository repository = DisabledParticipantRepository();
  String? startupError;
  try {
    final environment = BuildEnvironment.validate();
    FirebaseBackend? backend;
    if (environment == 'staging') {
      backend = await StagingBackend.connect();
    } else if (const bool.fromEnvironment('USE_FIREBASE_EMULATORS')) {
      backend = await EmulatorBackend.connect();
    }
    if (backend != null) {
      final live = FirebaseParticipantRepository(backend);
      repository = live;
      await live.restore();
    }
  } catch (error) {
    startupError = error.toString();
  }
  runApp(ParticipantApp(repository: repository, startupError: startupError));
}

// Retained for the original welcome widget test and external launch references.
class MyApp extends ParticipantApp {
  const MyApp({super.key});
}
