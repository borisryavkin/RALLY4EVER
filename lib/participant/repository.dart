import 'dart:async';

import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:cloud_functions/cloud_functions.dart';
import 'package:firebase_auth/firebase_auth.dart';
import 'package:firebase_storage/firebase_storage.dart';
import 'package:flutter/foundation.dart';
import 'package:geocoding/geocoding.dart';
import 'package:geolocator/geolocator.dart';
import 'package:google_sign_in/google_sign_in.dart';

import '../data/emulator_backend.dart';
import '../models/attendance_models.dart';

typedef Record = Map<String, dynamic>;

/// Thrown by [ParticipantRepository.sendPasswordReset] only for genuine rate
/// limiting. Every other outcome (including an unknown email) is swallowed
/// by the implementation so callers can't distinguish them.
class PasswordResetRateLimited implements Exception {}

const _fallbackFunctionsError =
    'Something went wrong completing that action. Please try again.';

/// Cloud Functions callables in this app always throw a short, single-line,
/// human-authored HttpsError message for expected business failures. A raw
/// platform-level failure (token/claim verification, an uncaught server
/// error) instead leaks internal diagnostic text through the same
/// exception type, so this is told apart by shape, not by error code alone.
String friendlyFunctionsError(FirebaseFunctionsException e) {
  final message = e.message;
  if (message == null || message.isEmpty) return _fallbackFunctionsError;
  final looksRaw =
      message.length > 140 ||
      message.contains('\n') ||
      RegExp(
        r'\bclaim\b|\btoken\b|\bstack\b|\bexception\b',
        caseSensitive: false,
      ).hasMatch(message);
  return looksRaw ? _fallbackFunctionsError : message;
}

/// Shared by every avatar in the app (see UserAvatar in user_avatar.dart) and
/// the onboarding photo step's own live preview.
String initialsFor(Record profile) {
  final firstName = profile['firstName'] as String? ?? '';
  return firstName.isEmpty ? 'M' : firstName.substring(0, 1).toUpperCase();
}

class RecentSignInRequired implements Exception {
  @override
  String toString() =>
      'Verify with Google once more to enable email sign-in securely.';
}

abstract class ParticipantRepository extends ChangeNotifier {
  DateTime now() => DateTime.now();
  String? uid;
  String? email;
  bool verified = false;
  bool ready = true;
  bool enabled = false;
  String? streamError;
  Record profile = {};
  // mobile/emergencyContact: not in `profile` -- see firestore.rules'
  // private/contact. Populated once `contactReady` is true.
  Record contact = {};
  bool contactReady = false;
  List<Record> programs = [];
  bool catalogueReady = false;
  String? catalogueError;
  List<Record> events = [],
      rsvps = [],
      checkins = [],
      forms = [],
      consents = [],
      feedbackRecords = [],
      notifications = [];
  Set<String> claimRoles = {};
  String? claimRole;
  bool googleUser = false;
  bool passwordUser = false;
  String? pendingGoogleEmail;
  // Coarse, device-only position for "near you" browsing (Play list, Map).
  // Never written to Firestore, logs or analytics -- used only to build the
  // on-device query/sort. See requestBrowseLocation. One of: idle,
  // requesting, granted, denied, deniedForever, servicesOff, timeout.
  String locationStatus = 'idle';
  Record? deviceLocation;
  String? nearbyLabel;
  StreamSubscription<Position>? _browsePositions;
  void stopBrowseLocation() {
    unawaited(_browsePositions?.cancel() ?? Future<void>.value());
    _browsePositions = null;
  }

  Future<void> requestBrowseLocation() async {
    if (locationStatus == 'requesting') return;
    locationStatus = 'requesting';
    notifyListeners();
    if (!await Geolocator.isLocationServiceEnabled()) {
      locationStatus = 'servicesOff';
      notifyListeners();
      return;
    }
    var permission = await Geolocator.checkPermission();
    if (permission == LocationPermission.denied) {
      permission = await Geolocator.requestPermission();
    }
    if (permission == LocationPermission.deniedForever) {
      locationStatus = 'deniedForever';
      notifyListeners();
      return;
    }
    if (permission == LocationPermission.denied) {
      locationStatus = 'denied';
      notifyListeners();
      return;
    }
    try {
      final p = await Geolocator.getCurrentPosition(
        locationSettings: const LocationSettings(
          accuracy: LocationAccuracy.high,
        ),
      ).timeout(const Duration(seconds: 6));
      deviceLocation = {'lat': p.latitude, 'lng': p.longitude};
      locationStatus = 'granted';
      notifyListeners();
      unawaited(_reverseGeocode(p.latitude, p.longitude));
      _browsePositions ??=
          Geolocator.getPositionStream(
            locationSettings: const LocationSettings(
              accuracy: LocationAccuracy.high,
              distanceFilter: 20,
            ),
          ).listen(
            (p) {
              deviceLocation = {'lat': p.latitude, 'lng': p.longitude};
              locationStatus = 'granted';
              notifyListeners();
            },
            onError: (_) {
              locationStatus = 'timeout';
              notifyListeners();
            },
            cancelOnError: true,
          );
    } catch (_) {
      // Timeout or a platform failure after permission was granted: fall
      // back the same way as a denial, never crash or hang the screen.
      locationStatus = 'timeout';
      notifyListeners();
    }
  }

  Future<void> _reverseGeocode(double lat, double lng) async {
    try {
      final places = await placemarkFromCoordinates(lat, lng);
      final name = places.firstOrNull?.locality?.trim();
      nearbyLabel = (name != null && name.isNotEmpty) ? name : null;
    } catch (_) {
      nearbyLabel = null;
    }
    notifyListeners();
  }

  bool get canAdmin =>
      verified &&
      profile['role'] == 'admin' &&
      (claimRole == 'admin' || claimRoles.contains('admin'));
  bool get canCoach =>
      verified &&
      (claimRole == 'coach' || claimRoles.contains('coach')) &&
      profile['coachEnabled'] != false &&
      profile['role'] != 'participant';
  String get role => canAdmin
      ? 'admin'
      : canCoach
      ? 'coach'
      : 'participant';
  Future<void> signInGoogle() => throw UnimplementedError();
  Future<void> addAppPassword(String password) => throw UnimplementedError();
  Future<void> reauthenticateGoogle() => throw UnimplementedError();
  Future<void> refreshAccess() => throw UnimplementedError();
  Future<void> refreshCatalogue() async {}
  Record? rsvp(String eventId) =>
      rsvps.where((d) => d['eventId'] == eventId).firstOrNull;
  Record? checkin(String eventId) =>
      checkins.where((d) => d['eventId'] == eventId).firstOrNull;
  bool countedIn(String eventId) =>
      rsvp(eventId) != null && rsvp(eventId)!['cancelledAt'] == null;
  bool signed(Record form) => consents.any(
    (c) => c['formId'] == form['id'] && c['version'] == form['version'],
  );
  List<Record> missingForms(Record event) => forms
      .where(
        (f) =>
            (event['requiredFormIds'] as List? ?? []).contains(f['id']) &&
            !signed(f),
      )
      .toList();
  Future<void> signIn(String email, String password) =>
      throw UnimplementedError();
  Future<void> signUp(String email, String password) =>
      throw UnimplementedError();
  Future<void> sendPasswordReset(String email) => throw UnimplementedError();
  Future<void> refreshVerification() => throw UnimplementedError();
  Future<void> signOut() => throw UnimplementedError();
  Future<void> saveProfile(Record changes) => throw UnimplementedError();
  Future<void> saveContact(Record changes) => throw UnimplementedError();

  /// Null means "remove the photo". Expects already-encoded JPEG bytes.
  Future<void> savePhoto(List<int>? jpegBytes) => throw UnimplementedError();
  Future<void> countMeIn(String eventId, {bool cancel = false}) =>
      throw UnimplementedError();
  Future<Record> countedPeople(String eventId) => throw UnimplementedError();

  /// Null if there's no photo (or it can't be reached); never throws.
  Future<String?> photoDownloadUrl() async => null;
  Future<void> signForm(Record form) => throw UnimplementedError();
  Future<Record> call(String name, Record data) => throw UnimplementedError();
  Future<Record> location() async {
    if (!await Geolocator.isLocationServiceEnabled()) {
      throw StateError('Turn on location services to check in.');
    }
    var permission = await Geolocator.checkPermission();
    if (permission == LocationPermission.denied) {
      permission = await Geolocator.requestPermission();
    }
    if (permission == LocationPermission.denied ||
        permission == LocationPermission.deniedForever) {
      throw StateError(
        'Allow location access to check your distance from the court.',
      );
    }
    final p = await Geolocator.getCurrentPosition();
    return {'lat': p.latitude, 'lng': p.longitude};
  }

  Future<void> feedback(
    String eventId,
    int rating,
    List<String> tags,
    String comment,
  ) => throw UnimplementedError();
  @override
  void dispose() {
    unawaited(_browsePositions?.cancel() ?? Future<void>.value());
    super.dispose();
  }
}

class DisabledParticipantRepository extends ParticipantRepository {}

class FirebaseParticipantRepository extends ParticipantRepository {
  FirebaseParticipantRepository(this.backend) {
    enabled = true;
  }
  final FirebaseBackend backend;
  final List<StreamSubscription<dynamic>> _subscriptions = [];
  Future<void> restore() async {
    final user = backend.auth.currentUser;
    if (user != null) await _enter(user);
  }

  Future<void> _enter(User user) async {
    email = user.email;
    verified = user.emailVerified;
    if (!verified) {
      uid = null;
      notifyListeners();
      return;
    }
    await _refreshClaims(user);
    final result = await call('registerIdentity', {});
    if (result['requiresSignIn'] == true) {
      await backend.auth.signOut();
      throw StateError(
        'This profile was merged. Sign in to your canonical account or contact the team.',
      );
    }
    for (final subscription in _subscriptions) {
      await subscription.cancel();
    }
    _subscriptions.clear();
    uid = user.uid;
    ready = false;
    final received = <String>{};
    void arrived(String source) {
      received.add(source);
      ready = received.length >= 8;
      notifyListeners();
    }

    void failed(Object error) {
      streamError = error.toString();
      ready = true;
      notifyListeners();
    }

    final db = backend.firestore;
    _subscriptions.add(
      db.doc('users/$uid').snapshots().listen((s) {
        profile = s.data() ?? {};
        if (profile['mergedInto'] != null) {
          unawaited(signOut());
          return;
        }
        arrived('profile');
      }, onError: failed),
    );
    contactReady = false;
    _subscriptions.add(
      db
          .doc('users/$uid/private/contact')
          .snapshots()
          .listen(
            (s) {
              contact = s.data() ?? {};
              contactReady = true;
              notifyListeners();
            },
            onError: (Object error) {
              // Not counted in `ready`: contact is a narrower, newer slice of
              // profile data and should never block the rest of the app.
              contactReady = true;
              notifyListeners();
            },
          ),
    );
    void watch(
      String collection,
      Query<Record> query,
      void Function(List<Record>) assign,
    ) {
      _subscriptions.add(
        query.snapshots().listen((s) {
          assign(s.docs.map((d) => {...d.data(), 'id': d.id}).toList());
          arrived(collection);
        }, onError: failed),
      );
    }

    watch(
      'events',
      db
          .collection('events')
          .where('status', whereIn: ['published', 'cancelled']),
      (v) {
        v.sort(
          (a, b) => dateOf(a['startsAt']).compareTo(dateOf(b['startsAt'])),
        );
        events = v;
      },
    );
    catalogueReady = false;
    catalogueError = null;
    _subscriptions.add(
      db
          .collection('programs')
          .where('status', isEqualTo: 'active')
          .snapshots()
          .listen(
            (snapshot) {
              programs =
                  snapshot.docs.map((d) => {...d.data(), 'id': d.id}).toList()
                    ..sort(
                      (a, b) =>
                          (a['name'] as String).compareTo(b['name'] as String),
                    );
              catalogueReady = true;
              notifyListeners();
            },
            onError: (Object error) {
              catalogueError = error.toString();
              catalogueReady = true;
              notifyListeners();
            },
          ),
    );
    watch(
      'rsvps',
      db.collection('rsvps').where('uid', isEqualTo: uid),
      (v) => rsvps = v,
    );
    watch(
      'checkins',
      db.collection('checkins').where('uid', isEqualTo: uid),
      (v) => checkins = v,
    );
    watch('forms', db.collection('forms'), (v) => forms = v);
    watch(
      'consents',
      db.collection('consents').where('uid', isEqualTo: uid),
      (v) => consents = v,
    );
    watch(
      'feedback',
      db.collection('feedback').where('uid', isEqualTo: uid),
      (v) => feedbackRecords = v,
    );
    watch(
      'notifications',
      db
          .collection('notifications')
          .where('uid', isEqualTo: uid)
          .where('type', isEqualTo: 'feedback'),
      (v) => notifications = v,
    );
    notifyListeners();
  }

  @override
  Future<void> refreshCatalogue() async {
    catalogueReady = false;
    catalogueError = null;
    notifyListeners();
    try {
      final rows = await backend.firestore
          .collection('programs')
          .where('status', isEqualTo: 'active')
          .get();
      programs = rows.docs.map((d) => {...d.data(), 'id': d.id}).toList();
    } catch (error) {
      catalogueError = error.toString();
    }
    catalogueReady = true;
    notifyListeners();
  }

  Future<void> _refreshClaims(User user) async {
    final token = await user.getIdTokenResult(true);
    claimRole = token.claims?['role'] as String?;
    claimRoles = Set<String>.from(token.claims?['roles'] as List? ?? []);
    googleUser = user.providerData.any((p) => p.providerId == 'google.com');
    passwordUser = user.providerData.any((p) => p.providerId == 'password');
  }

  @override
  Future<void> refreshAccess() async {
    final user = backend.auth.currentUser;
    if (user != null) {
      await _refreshClaims(user);
      notifyListeners();
    }
  }

  Future<({AuthCredential credential, String email})>
  _nativeGoogleIdentity() async {
    const serverId = String.fromEnvironment('GOOGLE_SERVER_CLIENT_ID');
    const iosClientId = String.fromEnvironment('FIREBASE_IOS_CLIENT_ID');
    await GoogleSignIn.instance.initialize(
      serverClientId: serverId.isEmpty ? null : serverId,
      clientId:
          defaultTargetPlatform == TargetPlatform.iOS && iosClientId.isNotEmpty
          ? iosClientId
          : null,
    );
    final account = await GoogleSignIn.instance.authenticate();
    final token = account.authentication.idToken;
    if (token == null) {
      throw StateError('Google did not return a verified identity.');
    }
    return (
      credential: GoogleAuthProvider.credential(idToken: token),
      email: normalizeEmail(account.email),
    );
  }

  @override
  Future<void> reauthenticateGoogle() async {
    final user = backend.auth.currentUser;
    if (user == null || user.uid != uid) throw StateError('Sign in first.');
    if (kIsWeb) {
      await user.reauthenticateWithPopup(
        GoogleAuthProvider()..setCustomParameters({
          'prompt': 'select_account',
          'login_hint': user.email ?? '',
        }),
      );
    } else {
      final identity = await _nativeGoogleIdentity();
      if (identity.email != normalizeEmail(user.email!)) {
        throw StateError('Choose the Google account for ${user.email}.');
      }
      await user.reauthenticateWithCredential(identity.credential);
    }
    if (backend.auth.currentUser?.uid != uid) {
      throw StateError('Account identity changed unexpectedly.');
    }
  }

  AuthCredential? _pendingGoogleCredential;
  @override
  Future<void> signInGoogle() async {
    UserCredential result;
    AuthCredential? googleCredential;
    String? googleEmail;
    try {
      if (kIsWeb) {
        final provider = GoogleAuthProvider()
          ..setCustomParameters({'prompt': 'select_account'});
        result = await backend.auth.signInWithPopup(provider);
      } else {
        final identity = await _nativeGoogleIdentity();
        googleEmail = identity.email;
        googleCredential = identity.credential;
        result = await backend.auth.signInWithCredential(googleCredential);
      }
    } on FirebaseAuthException catch (error) {
      if (error.code == 'account-exists-with-different-credential' &&
          (error.credential ?? googleCredential) != null &&
          (error.email ?? googleEmail) != null) {
        _pendingGoogleCredential = error.credential ?? googleCredential;
        pendingGoogleEmail = normalizeEmail(error.email ?? googleEmail!);
        throw StateError(
          'Sign in with email and your existing app password for $pendingGoogleEmail once to connect Google to the same profile.',
        );
      }
      rethrow;
    }
    _pendingGoogleCredential = null;
    pendingGoogleEmail = null;
    await _enter(result.user!);
  }

  @override
  Future<void> addAppPassword(String password) async {
    final user = backend.auth.currentUser;
    if (user == null ||
        !user.emailVerified ||
        user.email == null ||
        user.uid != uid) {
      throw StateError(
        'Sign in and verify your email before adding a password.',
      );
    }
    if (user.providerData.any((p) => p.providerId == 'password')) {
      throw StateError(
        'Email sign-in is already connected. Use Forgot password to reset it.',
      );
    }
    try {
      // updatePassword adds password sign-in to this authenticated UID without
      // changing its email. Avoid re-submitting the Google-owned email through
      // linkWithCredential (EMAIL_EXISTS on some Auth projects/emulators).
      await user.updatePassword(password);
      if (backend.auth.currentUser?.uid != uid) {
        throw StateError(
          'Account identity changed unexpectedly. Contact Rally4Ever.',
        );
      }
      await user.reload();
      await _refreshClaims(backend.auth.currentUser!);
      notifyListeners();
    } on FirebaseAuthException catch (error) {
      if (error.code == 'requires-recent-login') {
        throw RecentSignInRequired();
      }
      if (error.code == 'credential-already-in-use' ||
          error.code == 'email-already-in-use') {
        throw StateError(
          'This email is already connected to another account. Contact an admin; no profiles have been merged.',
        );
      }
      rethrow;
    }
  }

  @override
  Future<void> signIn(String email, String password) async {
    late UserCredential credential;
    try {
      credential = await backend.auth.signInWithEmailAndPassword(
        email: normalizeEmail(email),
        password: password,
      );
    } on FirebaseAuthException catch (error) {
      if ([
        'invalid-credential',
        'wrong-password',
        'user-not-found',
      ].contains(error.code)) {
        throw StateError(
          'Email and app password did not match. If you first used Google, sign in with Google and add an app password in Me → Sign-in methods.',
        );
      }
      rethrow;
    }
    final pending = _pendingGoogleCredential;
    final pendingEmail = pendingGoogleEmail;
    _pendingGoogleCredential = null;
    pendingGoogleEmail = null;
    if (pending != null &&
        pendingEmail == normalizeEmail(credential.user!.email!)) {
      try {
        await credential.user!.linkWithCredential(pending);
      } on FirebaseAuthException catch (error) {
        if (error.code != 'provider-already-linked') {
          throw StateError(
            'The sign-in methods could not be connected. Sign in to your original account or contact an admin.',
          );
        }
      }
    }
    await _enter(backend.auth.currentUser!);
  }

  @override
  Future<void> signUp(String email, String password) async {
    late UserCredential credential;
    try {
      credential = await backend.auth.createUserWithEmailAndPassword(
        email: normalizeEmail(email),
        password: password,
      );
    } on FirebaseAuthException catch (error) {
      if (error.code == 'email-already-in-use') {
        throw StateError(
          'This email already has an account. Sign in with Google or your app password. To add a password, use Me → Sign-in methods after signing in.',
        );
      }
      rethrow;
    }
    await credential.user!.sendEmailVerification();
    await _enter(credential.user!);
  }

  @override
  Future<void> sendPasswordReset(String email) async {
    try {
      await backend.auth.sendPasswordResetEmail(email: normalizeEmail(email));
    } on FirebaseAuthException catch (e) {
      if (e.code == 'too-many-requests') throw PasswordResetRateLimited();
      // Every other code (user-not-found, invalid-email, ...) is swallowed
      // so the caller always sees the same neutral outcome regardless of
      // whether the account exists.
    }
  }

  @override
  Future<void> refreshVerification() async {
    await backend.auth.currentUser?.reload();
    final user = backend.auth.currentUser;
    if (user != null) await _enter(user);
  }

  @override
  Future<void> signOut() async {
    for (final sub in _subscriptions) {
      await sub.cancel();
    }
    _subscriptions.clear();
    await backend.auth.signOut();
    uid = null;
    claimRole = null;
    claimRoles = {};
    googleUser = false;
    passwordUser = false;
    _pendingGoogleCredential = null;
    pendingGoogleEmail = null;
    email = null;
    verified = false;
    profile = {};
    contact = {};
    contactReady = false;
    events = [];
    programs = [];
    catalogueReady = false;
    catalogueError = null;
    rsvps = [];
    checkins = [];
    forms = [];
    consents = [];
    ready = true;
    notifyListeners();
  }

  @override
  Future<Record> call(String name, Record data) async {
    try {
      final result = await backend.functions
          .httpsCallable(name)
          .call<dynamic>(data);
      return Map<String, dynamic>.from(result.data as Map);
    } on FirebaseFunctionsException catch (e, stackTrace) {
      // Technical detail stays in the console; the UI only ever sees the
      // friendly message from friendlyFunctionsError.
      debugPrint(
        'Cloud Function "$name" failed: ${e.code} ${e.message}\n$stackTrace',
      );
      throw StateError(friendlyFunctionsError(e));
    }
  }

  @override
  Future<void> saveProfile(Record changes) async {
    await backend.firestore.doc('users/$uid').update({
      ...changes,
      'updatedAt': FieldValue.serverTimestamp(),
    });
    profile = {...profile, ...changes};
    notifyListeners();
  }

  @override
  Future<void> saveContact(Record changes) async {
    await backend.firestore.doc('users/$uid/private/contact').update({
      ...changes,
      'updatedAt': FieldValue.serverTimestamp(),
    });
    contact = {...contact, ...changes};
    notifyListeners();
  }

  @override
  Future<void> savePhoto(List<int>? jpegBytes) async {
    final ref = backend.storage.ref('profilePhotos/$uid/avatar.jpg');
    if (jpegBytes == null) {
      try {
        await ref.delete();
      } on FirebaseException catch (e) {
        if (e.code != 'object-not-found') rethrow;
      }
      await saveProfile({'photoUpdatedAt': null});
      return;
    }
    await ref.putData(
      Uint8List.fromList(jpegBytes),
      SettableMetadata(contentType: 'image/jpeg'),
    );
    await saveProfile({'photoUpdatedAt': FieldValue.serverTimestamp()});
  }

  // Resolving a Storage download URL is its own network round trip (the URL
  // itself is then cached on-disk/in-memory by CachedNetworkImage); cache it
  // per (uid, photoUpdatedAt) so every UserAvatar showing the same photo in
  // the same frame -- or across rebuilds, until the photo actually changes
  // -- reuses one resolved URL instead of re-resolving it each time.
  final Map<String, Future<String?>> _photoUrlCache = {};
  @override
  Future<String?> photoDownloadUrl() {
    final updatedAt = profile['photoUpdatedAt'];
    if (updatedAt == null || uid == null) return Future.value(null);
    final stamp = updatedAt is Timestamp
        ? updatedAt.millisecondsSinceEpoch
        : updatedAt;
    return _photoUrlCache.putIfAbsent('$uid:$stamp', () async {
      try {
        return await backend.storage
            .ref('profilePhotos/$uid/avatar.jpg')
            .getDownloadURL();
      } on FirebaseException {
        return null;
      }
    });
  }

  @override
  Future<void> countMeIn(String eventId, {bool cancel = false}) async {
    await call('setRsvp', {'eventId': eventId, 'cancel': cancel});
  }

  @override
  Future<Record> countedPeople(String eventId) =>
      call('getCountedIn', {'eventId': eventId});
  @override
  Future<void> signForm(Record form) async {
    final receipt = {
      'uid': uid,
      'formId': form['id'],
      'formType': form['formType'],
      'version': form['version'],
      'signedAt': FieldValue.serverTimestamp(),
    };
    await backend.firestore.doc('consents/${uid}_${form['id']}').set(receipt);
    consents = [...consents.where((c) => c['formId'] != form['id']), receipt];
    notifyListeners();
  }

  @override
  Future<void> feedback(
    String eventId,
    int rating,
    List<String> tags,
    String comment,
  ) => backend.firestore.doc('feedback/${eventId}_$uid').set({
    'uid': uid,
    'eventId': eventId,
    'rating': rating,
    'tags': tags,
    'comment': comment,
    'createdAt': FieldValue.serverTimestamp(),
  });
  @override
  void dispose() {
    for (final sub in _subscriptions) {
      unawaited(sub.cancel());
    }
    super.dispose();
  }
}

DateTime dateOf(dynamic value) => value is Timestamp
    ? value.toDate()
    : value is DateTime
    ? value
    : DateTime.tryParse('$value') ?? DateTime.fromMillisecondsSinceEpoch(0);

class CheckInLink {
  const CheckInLink(this.eventCode, this.secret);
  final String eventCode, secret;
  static CheckInLink parse(String raw) {
    final uri = Uri.tryParse(raw.trim());
    if (uri == null ||
        uri.scheme != 'https' ||
        uri.host != 'rally4ever.org' ||
        uri.hasPort ||
        uri.userInfo.isNotEmpty ||
        uri.fragment.isNotEmpty ||
        uri.pathSegments.length != 2 ||
        uri.pathSegments.first != 'c' ||
        !RegExp(r'^[A-Za-z0-9-]{1,128}$').hasMatch(uri.pathSegments.last) ||
        uri.queryParametersAll.length != 1 ||
        uri.queryParametersAll['k']?.length != 1 ||
        !RegExp(r'^[A-Za-z0-9_-]{43}$')
            .hasMatch(uri.queryParameters['k'] ?? '')) {
      throw const FormatException(
        'Scan a current Rally4Ever QR code from your coach.',
      );
    }
    return CheckInLink(uri.pathSegments.last, uri.queryParameters['k']!);
  }
}
