import 'dart:async';
import 'dart:convert';
import 'dart:math';

import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:cloud_functions/cloud_functions.dart';
import 'package:firebase_auth/firebase_auth.dart';
import 'package:firebase_storage/firebase_storage.dart';
import 'package:flutter/foundation.dart';
import 'package:geocoding/geocoding.dart';
import 'package:geolocator/geolocator.dart';
import 'package:google_sign_in/google_sign_in.dart';
import 'package:shared_preferences/shared_preferences.dart';

import '../data/emulator_backend.dart';
import '../models/attendance_models.dart';

typedef Record = Map<String, dynamic>;

/// Rally4Ever's Firebase "Web client" OAuth client (client_type 3 in
/// google-services.json), shared by every Android/iOS app in the
/// rally4ever-3adaf project. Not a secret -- it's the same value Google
/// ships inside every downloadable google-services.json -- so it's a safe
/// fallback for a dart-define config file that hasn't been filled in yet.
const _fallbackGoogleServerClientId =
    '55117668228-rf3r7a555us3ueufb73q122pej0bqe4h.apps.googleusercontent.com';

String _resolvedGoogleServerClientId() {
  const serverId = String.fromEnvironment('GOOGLE_SERVER_CLIENT_ID');
  return serverId.isEmpty || serverId.startsWith('REPLACE_WITH')
      ? _fallbackGoogleServerClientId
      : serverId;
}

/// GoogleSignIn.instance.initialize() must run exactly once for the life of
/// the app -- calling it again mid-flow (as the old code did, once per
/// sign-in attempt) is a known cause of Android's
/// GoogleSignInException(canceled, [16]) showing up for reasons that have
/// nothing to do with the user actually canceling. [connectParticipantRepository]
/// in app_bootstrap.dart awaits this once at startup; [_nativeGoogleIdentity]
/// below just awaits the same cached future, so a user who taps the Google
/// button before startup's call resolves still gets exactly one
/// initialize() call, never a second one.
Future<void>? _googleSignInReady;
Future<void> ensureGoogleSignInInitialized() {
  if (kIsWeb) return Future.value();
  return _googleSignInReady ??= Future(() async {
    const iosClientId = String.fromEnvironment('FIREBASE_IOS_CLIENT_ID');
    try {
      await GoogleSignIn.instance.initialize(
        serverClientId: _resolvedGoogleServerClientId(),
        clientId:
            defaultTargetPlatform == TargetPlatform.iOS &&
                iosClientId.isNotEmpty
            ? iosClientId
            : null,
      );
    } catch (_) {
      // A transient failure (e.g. Play Services not ready yet) shouldn't
      // permanently wedge every later Google sign-in attempt this session.
      _googleSignInReady = null;
      rethrow;
    }
  });
}

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

/// Thrown by [ParticipantRepository.call] for every Cloud Functions
/// failure. [reason] is the server's short machine-readable slug (from
/// functions/src/domain.ts's `fail()`, carried in the exception's
/// `details`) -- a caller that needs to react to a *specific* failure
/// (e.g. a stale-revision conflict) checks [reason] instead of
/// string-matching [message], which stays free to change wording without
/// breaking that logic. Everything else just shows [message] via
/// [friendlyError].
class FunctionsCallError implements Exception {
  const FunctionsCallError(this.code, this.reason, this.message);
  final String code;
  final String? reason;
  final String message;
  @override
  String toString() => message;
}

/// Optional name prefilling must remain compatible with deployed functions
/// that only accept the original email/token contract. Retry only the known
/// unknown-field rejection, never authentication, identity or network failures.
@visibleForTesting
Future<Record> registerIdentityCompatible(
  Future<Record> Function(String, Record) invoke, {
  String? firstNameHint,
}) async {
  final hint = firstNameHint?.trim();
  final payload = <String, dynamic>{
    if (hint != null && hint.isNotEmpty) 'firstNameHint': hint,
  };
  try {
    return await invoke('registerIdentity', payload);
  } on FunctionsCallError catch (error) {
    if (payload.isEmpty ||
        error.code != 'invalid-argument' ||
        error.reason != 'unknown-field') {
      rethrow;
    }
    return invoke('registerIdentity', {});
  }
}

/// Shown for any [GoogleSignInException] -- including a "canceled" one that
/// was never really a user cancellation, which is what a misconfigured
/// serverClientId or an unregistered signing-certificate fingerprint looks
/// like on Android. See [friendlyError] and app.dart's error banner, which
/// offers "Try again" / "Use email instead" specifically for this message.
const googleSignInFailedMessage =
    "Google sign-in didn't work this time. You can try again, or use your "
    'email instead.';

/// The one place every screen turns a caught exception into user-facing
/// text -- no screen should ever show a raw `e.toString()`, which can leak
/// an exception's class name, a stack hint, or raw platform text. Unknown
/// exception shapes fall back to a generic message and log the real
/// detail instead of guessing at how to shorten it.
String friendlyError(Object error) {
  if (error is FormatException) return error.message;
  if (error is FunctionsCallError) return error.message;
  if (error is StateError) return error.message;
  if (error is RecentSignInRequired) return error.toString();
  if (error is GoogleSignInException) {
    debugPrint(
      'GoogleSignInException ${error.code}: '
      '${error.description ?? error.details ?? ''}',
    );
    return googleSignInFailedMessage;
  }
  if (error is FirebaseException) {
    debugPrint('${error.plugin} error ${error.code}: ${error.message}');
    return switch (error.code) {
      'permission-denied' => "You don't have access to do that.",
      'unavailable' ||
      'network-request-failed' => 'Check your connection and try again.',
      'not-found' || 'object-not-found' =>
        'That could not be found. It may have been removed.',
      _ => 'Something went wrong. Please try again.',
    };
  }
  debugPrint('Unhandled error shown to the user as a generic message: $error');
  return 'Something went wrong. Please try again.';
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
  List<Record> venues = [];
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
  // Whether this device has ever completed a sign-in before -- decides
  // whether the account screen defaults to "Create account" (never seen
  // one) or "Welcome back" (has). Loaded from on-device storage; false
  // (so "Create account" shows) until that load resolves.
  bool hasSignedInBefore = false;
  // Last few location searches on this device (most recent first), shown
  // above the full suburb list -- never in place of it. In-memory only in
  // the base class; the real implementation persists on-device.
  List<String> recentLocationSearches = [];
  void recordLocationSearch(String value) {
    final trimmed = value.trim();
    if (trimmed.isEmpty) return;
    recentLocationSearches = [
      trimmed,
      ...recentLocationSearches.where(
        (v) => v.toLowerCase() != trimmed.toLowerCase(),
      ),
    ].take(5).toList();
    notifyListeners();
  }

  void clearRecentLocationSearches() {
    recentLocationSearches = [];
    notifyListeners();
  }

  // Details from the last no-account check-in on this device (email,
  // firstName, mobile, emergencyName, emergencyMobile), so a returning
  // no-account participant doesn't have to retype everything. In-memory
  // only in the base class; the real implementation persists on-device.
  Map<String, String> lastNoAppCheckIn = {};
  Map<String, String> anonymousCheckInTokens = {};
  String anonymousTokenFor(String eventId) =>
      anonymousCheckInTokens.putIfAbsent(
        eventId,
        () => base64Url
            .encode(List.generate(32, (_) => Random.secure().nextInt(256)))
            .replaceAll('=', ''),
      );
  void saveNoAppCheckIn(Map<String, String> details) {
    lastNoAppCheckIn = details;
  }

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
    } catch (_) {
      // Timeout or a platform failure after permission was granted: fall
      // back the same way as a denial, never crash or hang the screen.
      if (locationStatus != 'granted') locationStatus = 'timeout';
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
  List<String> requiredFormIds(Record event) => {
    'conduct',
    'waiver',
    ...((event['requiredFormIds'] as List?) ?? []).cast<String>(),
  }.toList();
  bool formPublished(Record form) =>
      form['publishedAt'] != null &&
      !dateOf(form['publishedAt']).isAfter(DateTime.now()) &&
      form['published'] != false &&
      form['status'] != 'draft' &&
      ((form['body'] ?? form['content'] ?? '') as String).trim().isNotEmpty;
  List<String> unavailableForms(Record event) =>
      requiredFormIds(event)
          .where((id) => !forms.any((f) => f['id'] == id && formPublished(f)))
          .toList();
  List<Record> missingForms(Record event) => forms
      .where(
        (f) =>
            requiredFormIds(event).contains(f['id']) &&
            formPublished(f) &&
            !signed(f),
      )
      .toList();
  Future<void> signIn(String email, String password) =>
      throw UnimplementedError();
  Future<void> signUp(String email, String password) =>
      throw UnimplementedError();
  Future<void> sendPasswordReset(String email) => throw UnimplementedError();
  Future<void> refreshVerification() => throw UnimplementedError();

  /// Cooldown is the caller's responsibility (see AccountForm) -- this
  /// always attempts to send.
  Future<void> resendVerificationEmail() => throw UnimplementedError();
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
  Future<String> uploadCataloguePhoto(
    String kind,
    String id,
    Uint8List bytes,
    ValueChanged<double> progress,
  ) => throw UnimplementedError();
  Future<Uint8List?> venuePhotoBytes(String url) async => null;
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
  SharedPreferencesAsync? _prefsOverride;
  SharedPreferencesAsync get _prefs =>
      _prefsOverride ??= SharedPreferencesAsync();

  /// Awaited by [connectParticipantRepository] before the repository ever
  /// reaches the widget tree, so [hasSignedInBefore] (which decides the
  /// account screen's default tab) and [recentLocationSearches] are
  /// correct on the very first build -- never a flash of the wrong one
  /// while on-device storage is still loading.
  Future<void> loadDeviceState() async {
    try {
      hasSignedInBefore =
          await _prefs.getBool('r4e_has_signed_in_before') ?? false;
      recentLocationSearches =
          await _prefs.getStringList('r4e_recent_location_searches') ?? [];
      final storedNoAppCheckIn = await _prefs.getString(
        'r4e_last_noapp_checkin',
      );
      if (storedNoAppCheckIn != null) {
        lastNoAppCheckIn = Map<String, String>.from(
          jsonDecode(storedNoAppCheckIn) as Map,
        );
      }
      final tokens = await _prefs.getString('r4e_anonymous_checkin_tokens');
      if (tokens != null) {
        anonymousCheckInTokens = Map<String, String>.from(
          jsonDecode(tokens) as Map,
        );
      }
      notifyListeners();
    } catch (_) {
      // On-device storage is unavailable (sandboxed test runner, denied
      // permission): keep the safe in-memory defaults rather than crash.
    }
  }

  @override
  String anonymousTokenFor(String eventId) {
    final token = super.anonymousTokenFor(eventId);
    unawaited(
      _prefs.setString(
        'r4e_anonymous_checkin_tokens',
        jsonEncode(anonymousCheckInTokens),
      ),
    );
    return token;
  }

  @override
  void saveNoAppCheckIn(Map<String, String> details) {
    super.saveNoAppCheckIn(details);
    unawaited(_prefs.setString('r4e_last_noapp_checkin', jsonEncode(details)));
  }

  @override
  void recordLocationSearch(String value) {
    super.recordLocationSearch(value);
    unawaited(
      _prefs.setStringList(
        'r4e_recent_location_searches',
        recentLocationSearches,
      ),
    );
  }

  @override
  void clearRecentLocationSearches() {
    super.clearRecentLocationSearches();
    unawaited(_prefs.remove('r4e_recent_location_searches'));
  }

  Future<void> restore() async {
    // Fired here (app startup), not awaited: most sessions never touch
    // Google sign-in, so startup shouldn't wait on it, but it still only
    // ever runs once -- see ensureGoogleSignInInitialized. A failure here
    // isn't shown to the user; _nativeGoogleIdentity retries it (and
    // surfaces any error) the moment someone actually taps Google sign-in.
    unawaited(
      ensureGoogleSignInInitialized().catchError(
        (Object e) => debugPrint('Google Sign-In did not initialize: $e'),
      ),
    );
    final user = backend.auth.currentUser;
    if (user != null) await _enter(user);
  }

  Future<void> _enter(User user) async {
    email = user.email;
    verified = user.emailVerified;
    if (!hasSignedInBefore) {
      hasSignedInBefore = true;
      unawaited(_prefs.setBool('r4e_has_signed_in_before', true));
    }
    if (!verified) {
      uid = null;
      notifyListeners();
      return;
    }
    await _refreshClaims(user);
    // A courtesy prefill for a brand-new profile's About You step -- the
    // backend only ever applies it the first time a profile is created,
    // never overwriting a real one on a returning sign-in.
    final firstNameHint = user.displayName?.trim().split(' ').firstOrNull;
    final result = await registerIdentityCompatible(
      call,
      firstNameHint: firstNameHint,
    );
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
      debugPrint('Profile stream failed: $error');
      streamError = friendlyError(error);
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
    watch('venues', db.collection('venues'), (v) => venues = v);
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
    await ensureGoogleSignInInitialized();
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
        try {
          final identity = await _nativeGoogleIdentity();
          googleEmail = identity.email;
          googleCredential = identity.credential;
          result = await backend.auth.signInWithCredential(googleCredential);
        } on GoogleSignInException catch (error) {
          // The Android Credential Manager path reports "canceled" even
          // when the user never actually canceled (a misconfigured
          // serverClientId, an unregistered signing-certificate
          // fingerprint, or a transient Play Services issue all look the
          // same from here). Never leave the user stuck on that: fall
          // back to a full browser-based OAuth flow, which doesn't go
          // through Credential Manager at all, before giving up.
          debugPrint(
            'Native Google credential failed (${error.code}); falling back '
            'to browser-based sign-in: $error',
          );
          final provider = GoogleAuthProvider()
            ..setCustomParameters({'prompt': 'select_account'});
          result = await backend.auth.signInWithProvider(provider);
        }
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
          'Email or app password did not match. Use Google, or choose Set or reset app password below.',
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
  Future<void> resendVerificationEmail() async {
    final user = backend.auth.currentUser;
    if (user == null) throw StateError('Sign in first.');
    await user.sendEmailVerification();
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
      throw FunctionsCallError(
        e.code,
        (e.details is Map) ? (e.details as Map)['reason'] as String? : null,
        friendlyFunctionsError(e),
      );
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
  Future<String> uploadCataloguePhoto(
    String kind,
    String id,
    Uint8List bytes,
    ValueChanged<double> progress,
  ) async {
    if (!canAdmin || !['session', 'venue'].contains(kind)) {
      throw StateError('Admin access required');
    }
    final folder = kind == 'venue' ? 'venues' : 'sessions';
    final ref = backend.storage.ref(
      '$folder/$id/${DateTime.now().microsecondsSinceEpoch}.jpg',
    );
    final task = ref.putData(
      bytes,
      SettableMetadata(
        contentType: 'image/jpeg',
        cacheControl: 'public,max-age=3600',
      ),
    );
    final subscription = task.snapshotEvents.listen(
      (s) =>
          progress(s.totalBytes == 0 ? 0 : s.bytesTransferred / s.totalBytes),
    );
    try {
      await task;
    } finally {
      await subscription.cancel();
    }
    return 'https://firebasestorage.googleapis.com/v0/b/${ref.bucket}/o/${Uri.encodeComponent(ref.fullPath)}?alt=media';
  }

  @override
  Future<Uint8List?> venuePhotoBytes(String url) =>
      backend.storage.refFromURL(url).getData(5 * 1024 * 1024);

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
        !{
          'rally4ever.org',
          'rally4ever-checkin-3adaf.web.app',
        }.contains(uri.host) ||
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
        "That doesn't look like a RALLY4EVER session code. Ask your coach to show the current one.",
      );
    }
    return CheckInLink(uri.pathSegments.last, uri.queryParameters['k']!);
  }
}
