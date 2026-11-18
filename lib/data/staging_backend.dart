import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:cloud_functions/cloud_functions.dart';
import 'package:firebase_auth/firebase_auth.dart';
import 'package:firebase_core/firebase_core.dart';

import 'build_environment.dart';
import 'emulator_backend.dart';

/// Real staging transport; deliberately has no emulator connection calls.
/// Deploying its backend is a separate, approval-gated release step.
class StagingBackend implements FirebaseBackend {
  StagingBackend._(this.auth, this.firestore, this.functions);
  @override
  final FirebaseAuth auth;
  @override
  final FirebaseFirestore firestore;
  @override
  final FirebaseFunctions functions;

  static Future<StagingBackend> connect() async {
    if (BuildEnvironment.validate() != 'staging') {
      throw StateError('Staging transport requires the staging flavor');
    }
    const apiKey = String.fromEnvironment('FIREBASE_API_KEY');
    const appId = String.fromEnvironment('FIREBASE_APP_ID');
    const senderId = String.fromEnvironment('FIREBASE_MESSAGING_SENDER_ID');
    const project = String.fromEnvironment('FIREBASE_PROJECT_ID');
    if (apiKey.isEmpty || appId.isEmpty || senderId.isEmpty) {
      throw StateError(
        'Supply the registered staging app Firebase client config',
      );
    }
    // The default app, not a named one: several native Firebase iOS SDK
    // paths outside this app's own control (Installations/App Check-style
    // diagnostics inside Auth/Firestore/Functions pods) assume a default
    // app exists, and throw core/no-app if only a named app was ever
    // configured. Only one backend is ever connected per process, so there
    // is no need for a second, named app here.
    final app = await Firebase.initializeApp(
      options: const FirebaseOptions(
        apiKey: apiKey,
        appId: appId,
        messagingSenderId: senderId,
        projectId: project,
        iosBundleId: 'org.rally4ever',
        iosClientId: String.fromEnvironment('FIREBASE_IOS_CLIENT_ID'),
        authDomain: String.fromEnvironment('FIREBASE_AUTH_DOMAIN'),
      ),
    );
    return StagingBackend._(
      FirebaseAuth.instanceFor(app: app),
      FirebaseFirestore.instanceFor(app: app),
      FirebaseFunctions.instanceFor(app: app, region: 'australia-southeast1'),
    );
  }
}
