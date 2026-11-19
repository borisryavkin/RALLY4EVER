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
  // Coarse, device-only position for "near you" browsing (Play list, Map).
  // Never written to Firestore, logs or analytics -- used only to build the
  // on-device query/sort. See requestBrowseLocation. One of: idle,
  // requesting, granted, denied, deniedForever, servicesOff, timeout.
  String locationStatus = 'idle';
  Record? deviceLocation;
  String? nearbyLabel;
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
          accuracy: LocationAccuracy.low,
        ),
      ).timeout(const Duration(seconds: 6));
      deviceLocation = {'lat': p.latitude, 'lng': p.longitude};
      locationStatus = 'granted';
      notifyListeners();
      unawaited(_reverseGeocode(p.latitude, p.longitude));
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
      db.doc('users/$uid/private/contact').snapshots().listen(
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
          .where('status', whereIn: ['active', 'archived'])
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
          .where('status', whereIn: ['active', 'archived'])
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
  }

  @override
  Future<void> refreshAccess() async {
    final user = backend.auth.currentUser;
    if (user != null) {
      await _refreshClaims(user);
      notifyListeners();
    }
  }

  @override
  Future<void> signInGoogle() async {
    UserCredential result;
    if (kIsWeb) {
      final provider = GoogleAuthProvider()
        ..setCustomParameters({'prompt': 'select_account'});
      result = await backend.auth.signInWithPopup(provider);
    } else {
      const serverId = String.fromEnvironment('GOOGLE_SERVER_CLIENT_ID');
      const iosClientId = String.fromEnvironment('FIREBASE_IOS_CLIENT_ID');
      await GoogleSignIn.instance.initialize(
        serverClientId: serverId.isEmpty ? null : serverId,
        clientId:
            defaultTargetPlatform == TargetPlatform.iOS &&
                iosClientId.isNotEmpty
            ? iosClientId
            : null,
      );
      final account = await GoogleSignIn.instance.authenticate();
      final idToken = account.authentication.idToken;
      if (idToken == null) {
        throw StateError('Google did not return a verified identity.');
      }
      result = await backend.auth.signInWithCredential(
        GoogleAuthProvider.credential(idToken: idToken),
      );
    }
    await _enter(result.user!);
  }

  @override
  Future<void> signIn(String email, String password) async {
    final credential = await backend.auth.signInWithEmailAndPassword(
      email: normalizeEmail(email),
      password: password,
    );
    await _enter(credential.user!);
  }

  @override
  Future<void> signUp(String email, String password) async {
    final credential = await backend.auth.createUserWithEmailAndPassword(
      email: normalizeEmail(email),
      password: password,
    );
    await credential.user!.sendEmailVerification();
    await _enter(credential.user!);
  }

  @override
  Future<void> sendPasswordReset(String email) async {
    try {
      await backend.auth.sendPasswordResetEmail(
        email: normalizeEmail(email),
      );
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

  @override
  Future<String?> photoDownloadUrl() async {
    if (profile['photoUpdatedAt'] == null) return null;
    try {
      return await backend.storage
          .ref('profilePhotos/$uid/avatar.jpg')
          .getDownloadURL();
    } on FirebaseException {
      return null;
    }
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
