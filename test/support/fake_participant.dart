import 'package:rally4ever/participant/repository.dart';

class FakeParticipantRepository extends ParticipantRepository {
  FakeParticipantRepository({
    bool authenticated = true,
    bool counted = true,
    String? attendance,
  }) {
    enabled = true;
    uid = authenticated ? 'participant-1' : null;
    email = authenticated ? 'priya@example.test' : null;
    verified = authenticated;
    profile = {
      'uid': 'participant-1',
      'firstName': 'Priya',
      'lastName': 'Lal',
      'postcode': '2022',
      'mobile': '0400000000',
      'emergencyContact': {'name': 'Mei Lal', 'mobile': '0400000001'},
      'injuries': '',
      'role': 'participant',
      'mergedInto': null,
      'about': {},
      'preferences': {
        'useInReports': false,
        'wellbeingCheckIns': false,
        'showInWhosGoing': true,
        'marketingEmails': false,
      },
    };
    final now = this.now();
    events = [
      {
        'id': 'event-1',
        'eventId': 'event-1',
        'code': 'EVENT-1',
        'name': 'Weeknight Rally',
        'sport': 'Tennis',
        'startsAt': now.subtract(const Duration(minutes: 5)),
        'endsAt': now.add(const Duration(hours: 1)),
        'timezone': 'Australia/Sydney',
        'coachUids': ['coach-1'],
        'venue': {
          'name': 'Waverley Park, Bondi Junction',
          'lat': -33.8926,
          'lng': 151.2511,
        },
        'geofenceRadiusM': 150,
        'requiredFormIds': ['conduct', 'waiver'],
      },
      {
        'id': 'event-2',
        'eventId': 'event-2',
        'code': 'EVENT-2',
        'name': 'Saturday Social',
        'sport': 'Pickleball',
        'startsAt': now.add(const Duration(days: 2)),
        'endsAt': now.add(const Duration(days: 2, hours: 1)),
        'timezone': 'Australia/Sydney',
        'coachUids': ['coach-2'],
        'venue': {
          'name': 'Bondi Beach Courts',
          'lat': -33.8915,
          'lng': 151.2767,
        },
        'geofenceRadiusM': 150,
        'requiredFormIds': ['conduct', 'waiver'],
      },
      {
        'id': 'event-3',
        'eventId': 'event-3',
        'code': 'EVENT-3',
        'name': 'Tuesday Rally',
        'sport': 'Tennis',
        'startsAt': now.subtract(const Duration(hours: 5)),
        'endsAt': now.subtract(const Duration(hours: 4)),
        'timezone': 'Australia/Sydney',
        'coachUids': ['coach-1'],
        'venue': {'name': 'Waverley Park', 'lat': -33.8926, 'lng': 151.2511},
        'geofenceRadiusM': 150,
        'requiredFormIds': ['conduct', 'waiver'],
      },
    ];
    if (counted) {
      rsvps = [
        {
          'uid': uid,
          'eventId': 'event-1',
          'createdAt': now,
          'cancelledAt': null,
          'source': 'coach-added',
        },
      ];
    }
    checkins = [record('event-3', 'confirmed')];
    if (attendance != null) checkins.add(record('event-1', attendance));
    forms = [
      {
        'id': 'conduct',
        'formType': 'conduct',
        'version': 1,
        'title': 'Code of conduct',
        'content': 'Demo agreement for local testing. Be kind and inclusive, respect other players, and follow your coach’s guidance.',
      },
      {
        'id': 'waiver',
        'formType': 'waiver',
        'version': 1,
        'title': 'Liability waiver',
        'content': 'Demo agreement for local testing. Play at a pace that feels right for you. Tell the coach about any injury or concern before joining in. Approved form wording will be supplied before release.',
      },
    ];
    consents = [
      for (final form in forms)
        {'uid': uid, 'formId': form['id'], 'version': 1, 'signedAt': now},
    ];
  }
  Record record(String eventId, String status) => {
    'eventId': eventId,
    'uid': uid,
    'scannedAt': now(),
    'method': 'app',
    'status': status,
    'lat': -33.8926,
    'lng': 151.2511,
    'distanceM': 23.0,
    'walkIn': false,
    'corrections': [],
    'confirmedBy': status == 'confirmed' ? 'coach-1' : null,
  };
  DateTime clock = DateTime.utc(2026, 11, 17, 7, 35);
  @override
  DateTime now() => clock;
  @override
  Future<void> signInGoogle() async {
    googleUser = true;
    uid = 'participant-1';
    email = 'workspace@rally4ever.org';
    verified = true;
    notifyListeners();
  }

  @override
  Future<void> refreshAccess() async {
    calls.add('refreshAccess');
    notifyListeners();
  }

  String? checkInError;
  Record? simulatedLocation;
  final calls = <String>[];
  @override
  Future<void> signIn(String email, String password) async {
    uid = 'participant-1';
    this.email = email;
    verified = true;
    notifyListeners();
  }

  @override
  Future<void> signUp(String email, String password) async {
    this.email = email;
    verified = false;
    notifyListeners();
  }

  bool passwordResetRateLimited = false;
  @override
  Future<void> sendPasswordReset(String email) async {
    calls.add('sendPasswordReset');
    if (passwordResetRateLimited) throw PasswordResetRateLimited();
  }

  @override
  Future<void> refreshVerification() async {
    verified = true;
    uid = 'participant-1';
    notifyListeners();
  }

  @override
  Future<void> signOut() async {
    uid = null;
    email = null;
    notifyListeners();
  }

  @override
  Future<void> saveProfile(Record changes) async {
    profile = {...profile, ...changes};
    notifyListeners();
  }

  @override
  Future<void> saveContact(Record changes) async {
    calls.add('saveContact');
    contact = {...contact, ...changes};
    notifyListeners();
  }

  List<int>? savedPhotoBytes;
  bool photoRemoved = false;
  @override
  Future<void> savePhoto(List<int>? jpegBytes) async {
    calls.add('savePhoto');
    if (jpegBytes == null) {
      photoRemoved = true;
      profile = {...profile, 'photoUpdatedAt': null};
    } else {
      savedPhotoBytes = jpegBytes;
      profile = {...profile, 'photoUpdatedAt': DateTime.now()};
    }
    notifyListeners();
  }

  @override
  Future<void> countMeIn(String eventId, {bool cancel = false}) async {
    rsvps = [
      ...rsvps.where((r) => r['eventId'] != eventId),
      {
        'uid': uid,
        'eventId': eventId,
        'createdAt': now(),
        'cancelledAt': cancel ? now() : null,
        'source': 'app',
      },
    ];
    notifyListeners();
  }

  @override
  Future<Record> countedPeople(String eventId) async => {
    'count': 4,
    'people': [
      {'label': 'Priya', 'initials': 'P', 'isYou': true},
      {'label': 'Mei', 'initials': 'M', 'isYou': false},
      {'label': 'Tom', 'initials': 'T', 'isYou': false},
      {'label': 'Aisha', 'initials': 'A', 'isYou': false},
    ],
  };
  @override
  Future<void> signForm(Record form) async {
    consents = [
      ...consents.where((c) => c['formId'] != form['id']),
      {
        'uid': uid,
        'formId': form['id'],
        'version': form['version'],
        'signedAt': now(),
      },
    ];
    notifyListeners();
  }

  @override
  Future<Record> location() async =>
      simulatedLocation ?? {'lat': -33.8926, 'lng': 151.2511};
  @override
  Future<Record> call(String name, Record data) async {
    calls.add(name);
    if (name == 'checkIn') {
      if (checkInError != null) throw StateError(checkInError!);
      checkins = [
        ...checkins.where((c) => c['eventId'] != 'event-1'),
        record('event-1', 'pending'),
      ];
      notifyListeners();
      return {
        'checkinId': 'event-1_$uid',
        'eventId': 'event-1',
        'status': 'pending',
      };
    }
    if (name == 'coachOverview') return {'events': [], 'pending': []};
    if (name == 'listUsers') {
      return {
        'users': [
          {
            'uid': 'participant-2',
            'email': 'mei@rally4ever.org',
            'firstName': 'Mei',
            'role': 'coach',
            'coachEnabled': true,
            'mergedInto': null,
          },
        ],
        'events': [
          {
            'eventId': 'event-1',
            'name': 'Weeknight Rally',
            'coachUids': ['participant-2'],
          },
        ],
        'cursor': null,
      };
    }
    if (name == 'getNoAppForms') return {'forms': forms};
    return {};
  }

  @override
  Future<void> feedback(
    String eventId,
    int rating,
    List<String> tags,
    String comment,
  ) async {
    calls.add('feedback:$rating');
  }

  void confirm() {
    checkins = [
      ...checkins.where((c) => c['eventId'] != 'event-1'),
      record('event-1', 'confirmed'),
    ];
    notifyListeners();
  }
}
