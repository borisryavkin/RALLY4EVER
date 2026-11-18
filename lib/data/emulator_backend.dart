import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:cloud_functions/cloud_functions.dart';
import 'package:firebase_auth/firebase_auth.dart';
import 'package:firebase_core/firebase_core.dart';
import 'package:firebase_storage/firebase_storage.dart';

import '../models/attendance_models.dart';
import 'emulator_settings.dart';

/// Explicit development opt-in; loopback by default, private LAN only by flag.
/// There is deliberately no production initialization path.
abstract interface class FirebaseBackend {
  FirebaseAuth get auth;
  FirebaseFirestore get firestore;
  FirebaseFunctions get functions;
  FirebaseStorage get storage;
}

class EmulatorBackend implements FirebaseBackend {
  EmulatorBackend._(
    this.app,
    this.auth,
    this.firestore,
    this.functions,
    this.storage,
    this.settings,
  );
  static const projectId = EmulatorSettings.projectId;
  final FirebaseApp app;
  @override
  final FirebaseAuth auth;
  @override
  final FirebaseFirestore firestore;
  @override
  final FirebaseFunctions functions;
  @override
  final FirebaseStorage storage;
  final EmulatorSettings settings;

  static String validateHost(
    String host, {
    bool lanTesting = false,
    String lanHost = '',
  }) => EmulatorSettings.resolve(
    host: host,
    lanTesting: lanTesting,
    lanHost: lanHost,
  ).host;

  static Future<EmulatorBackend> connect({
    bool enabled = const bool.fromEnvironment('USE_FIREBASE_EMULATORS'),
    String host = const String.fromEnvironment(
      'FIREBASE_EMULATOR_HOST',
      defaultValue: '',
    ),
    bool lanTesting = const bool.fromEnvironment('LAN_TESTING'),
    String lanHost = const String.fromEnvironment('LAN_HOST'),
    String requestedProjectId = const String.fromEnvironment(
      'FIREBASE_PROJECT_ID',
      defaultValue: projectId,
    ),
  }) async {
    if (!enabled) throw StateError('Enable USE_FIREBASE_EMULATORS explicitly');
    final settings = EmulatorSettings.resolve(
      host: host,
      lanTesting: lanTesting,
      lanHost: lanHost,
      requestedProjectId: requestedProjectId,
    );
    final emulatorHost = settings.host;
    // The default app, matching StagingBackend: using a named app can make
    // some native Firebase iOS SDK paths outside Dart's control throw
    // core/no-app when no default app was ever configured. Only one backend
    // is ever connected per process, so there is no need for a named one.
    final app = await Firebase.initializeApp(
      options: const FirebaseOptions(
        apiKey: 'demo-api-key',
        appId: '1:123456789:web:rally4ever-demo',
        messagingSenderId: '123456789',
        projectId: projectId,
        authDomain: 'demo-rally4ever.firebaseapp.com',
      ),
    );
    final auth = FirebaseAuth.instanceFor(app: app);
    final firestore = FirebaseFirestore.instanceFor(app: app);
    // Connect before making any Auth or Firestore request. No production fallback.
    await auth.useAuthEmulator(emulatorHost, 9099);
    firestore.settings = const Settings(persistenceEnabled: false);
    firestore.useFirestoreEmulator(emulatorHost, 8080);
    final functions = FirebaseFunctions.instanceFor(
      app: app,
      region: 'australia-southeast1',
    );
    functions.useFunctionsEmulator(emulatorHost, 5001);
    final storage = FirebaseStorage.instanceFor(app: app);
    storage.useStorageEmulator(emulatorHost, 9199);
    return EmulatorBackend._(app, auth, firestore, functions, storage, settings);
  }
}

class AuthSession {
  const AuthSession(this.user, this.profile);
  final User user;
  final UserProfile profile;
  AppRole get role => profile.role;
}

class RallyAuthRepository {
  RallyAuthRepository(this.backend);
  final EmulatorBackend backend;

  Future<AuthSession> signIn(String email, String password) async {
    final credential = await backend.auth.signInWithEmailAndPassword(
      email: normalizeEmail(email),
      password: password,
    );
    final user = credential.user!;
    if (!user.emailVerified) {
      await backend.auth.signOut();
      throw StateError('Verify your email before continuing');
    }
    try {
      final snapshot = await backend.firestore
          .collection('users')
          .doc(user.uid)
          .get();
      if (!snapshot.exists) {
        throw StateError('Profile provisioning is required');
      }
      final token = await user.getIdTokenResult(true);
      final profile = UserProfile.fromMap(
        snapshot.data()!,
        claimRole: token.claims?['role'] as String?,
      );
      if (!profile.active ||
          profile.uid != user.uid ||
          profile.emailLower != normalizeEmail(user.email!)) {
        throw StateError('Profile identity requires resolution');
      }
      return AuthSession(user, profile);
    } catch (_) {
      await backend.auth.signOut();
      rethrow;
    }
  }

  Future<void> signOut() => backend.auth.signOut();
}

/// Read contracts for future UI. No client attendance/role/identity write APIs.
class RallyDataRepository {
  RallyDataRepository(this.firestore);
  final FirebaseFirestore firestore;

  Stream<List<RallyEvent>> publishedEvents() => firestore
      .collection('events')
      .where('status', isEqualTo: 'published')
      .orderBy('startsAt')
      .snapshots()
      .map(
        (snapshot) => snapshot.docs
            .map((doc) => RallyEvent.fromMap(doc.id, doc.data()))
            .toList(),
      );

  Stream<List<RallyEvent>> coachEvents(String uid) => firestore
      .collection('events')
      .where('coachUids', arrayContains: uid)
      .orderBy('startsAt')
      .snapshots()
      .map(
        (snapshot) => snapshot.docs
            .map((doc) => RallyEvent.fromMap(doc.id, doc.data()))
            .toList(),
      );

  Stream<List<RsvpRecord>> myRsvps(String uid) => firestore
      .collection('rsvps')
      .where('uid', isEqualTo: uid)
      .orderBy('createdAt', descending: true)
      .snapshots()
      .map(
        (snapshot) =>
            snapshot.docs.map((doc) => RsvpRecord.fromMap(doc.data())).toList(),
      );

  Stream<CheckInRecord?> attendance(String eventId, String uid) => firestore
      .collection('checkins')
      .where('uid', isEqualTo: uid)
      .where('eventId', isEqualTo: eventId)
      .snapshots()
      .map(
        (snapshot) => snapshot.docs.isEmpty
            ? null
            : CheckInRecord.fromMap(snapshot.docs.single.data()),
      );
}
