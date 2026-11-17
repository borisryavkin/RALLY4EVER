import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:cloud_functions/cloud_functions.dart';
import 'package:firebase_auth/firebase_auth.dart';
import 'package:firebase_core/firebase_core.dart';

import '../models/attendance_models.dart';

/// Explicit opt-in; not wired into the prototype UI until the participant stage.
/// There is deliberately no production initialization path.
class EmulatorBackend {
  EmulatorBackend._(this.app, this.auth, this.firestore, this.functions);
  static const projectId = 'demo-rally4ever';
  final FirebaseApp app;
  final FirebaseAuth auth;
  final FirebaseFirestore firestore;
  final FirebaseFunctions functions;

  static String validateHost(String host) {
    // Android emulator uses 10.0.2.2 to reach the machine's loopback interface.
    if (!const ['localhost', '127.0.0.1', '10.0.2.2'].contains(host)) {
      throw ArgumentError.value(
        host,
        'host',
        'Only local emulator hosts allowed',
      );
    }
    return host;
  }

  static Future<EmulatorBackend> connect({
    bool enabled = const bool.fromEnvironment('USE_FIREBASE_EMULATORS'),
    String host = const String.fromEnvironment(
      'FIREBASE_EMULATOR_HOST',
      defaultValue: '127.0.0.1',
    ),
  }) async {
    if (!enabled) throw StateError('Enable USE_FIREBASE_EMULATORS explicitly');
    validateHost(host);
    final app = await Firebase.initializeApp(
      name: 'rally4ever-emulator',
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
    await auth.useAuthEmulator(host, 9099);
    firestore.settings = const Settings(persistenceEnabled: false);
    firestore.useFirestoreEmulator(host, 8080);
    final functions = FirebaseFunctions.instanceFor(
      app: app,
      region: 'australia-southeast1',
    );
    functions.useFunctionsEmulator(host, 5001);
    return EmulatorBackend._(app, auth, firestore, functions);
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
