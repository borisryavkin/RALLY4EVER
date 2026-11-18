import 'package:flutter/material.dart';
import 'package:timezone/data/latest.dart' as tz;

import 'app_bootstrap.dart';
import 'participant/app.dart';

void main() {
  WidgetsFlutterBinding.ensureInitialized();
  tz.initializeTimeZones();
  runApp(const AppBootstrap());
}

// Retained for the original welcome widget test and external launch references.
class MyApp extends ParticipantApp {
  const MyApp({super.key});
}
