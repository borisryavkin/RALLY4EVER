import 'package:cloud_firestore/cloud_firestore.dart';

String normalizeEmail(String email) => email.trim().toLowerCase();
String attendanceId(String eventId, String uid) => '${eventId}_$uid';
String consentId(String uid, String formId) => '${uid}_$formId';

enum AppRole {
  participant,
  coach,
  admin;

  /// Unknown roles never gain privileges. A profile role overrides stale claims.
  static AppRole resolve({String? profileRole, String? claimRole}) {
    final role = AppRole.values.firstWhere(
      (role) => role.name == (profileRole ?? claimRole),
      orElse: () => AppRole.participant,
    );
    return role == AppRole.coach && claimRole != 'coach'
        ? AppRole.participant
        : role;
  }
}

enum CheckInStatus { pending, confirmed, rejected }

enum CheckInMethod { app, camera, manual }

enum RsvpSource { app, coachAdded }

class UserProfile {
  const UserProfile({
    required this.uid,
    required this.emailLower,
    required this.role,
    required this.firstName,
    required this.lastName,
    required this.mobile,
    required this.emergencyContact,
    required this.injuries,
    this.mergedInto,
  });

  final String uid, emailLower, firstName, lastName, mobile, injuries;
  final AppRole role;
  final String? mergedInto;
  final Map<String, dynamic> emergencyContact;
  bool get active => mergedInto == null;

  factory UserProfile.fromMap(Map<String, dynamic> data, {String? claimRole}) =>
      UserProfile(
        uid: data['uid'] as String,
        emailLower: data['emailLower'] as String,
        role: AppRole.resolve(
          profileRole: data['coachEnabled'] == false && data['role'] == 'coach'
              ? 'participant'
              : data['role'] as String?,
          claimRole: claimRole,
        ),
        firstName: data['firstName'] as String,
        lastName: data['lastName'] as String,
        mobile: data['mobile'] as String,
        emergencyContact: Map<String, dynamic>.from(
          data['emergencyContact'] as Map,
        ),
        injuries: data['injuries'] as String,
        mergedInto: data['mergedInto'] as String?,
      );
}

class RallyEvent {
  const RallyEvent({
    required this.id,
    required this.code,
    required this.name,
    required this.startsAt,
    required this.endsAt,
    required this.timezone,
    required this.coachUids,
    required this.venue,
    required this.geofenceRadiusM,
    required this.requiredFormIds,
  });
  final String id, code, name, timezone;
  final DateTime startsAt, endsAt;
  final List<String> coachUids, requiredFormIds;
  final Map<String, dynamic> venue;
  final double geofenceRadiusM;
  DateTime get checkInOpensAt => startsAt.subtract(const Duration(minutes: 10));

  factory RallyEvent.fromMap(String id, Map<String, dynamic> data) =>
      RallyEvent(
        id: id,
        code: data['code'] as String,
        name: data['name'] as String,
        startsAt: (data['startsAt'] as Timestamp).toDate(),
        endsAt: (data['endsAt'] as Timestamp).toDate(),
        timezone: data['timezone'] as String,
        coachUids: List<String>.from(data['coachUids'] as List),
        venue: Map<String, dynamic>.from(data['venue'] as Map),
        geofenceRadiusM: (data['geofenceRadiusM'] as num).toDouble(),
        requiredFormIds: List<String>.from(data['requiredFormIds'] as List),
      );
}

class RsvpRecord {
  const RsvpRecord({
    required this.eventId,
    required this.uid,
    required this.createdAt,
    required this.source,
    this.cancelledAt,
  });
  final String eventId, uid;
  final DateTime createdAt;
  final DateTime? cancelledAt;
  final RsvpSource source;
  bool get countedIn => cancelledAt == null;
  factory RsvpRecord.fromMap(Map<String, dynamic> d) => RsvpRecord(
    eventId: d['eventId'] as String,
    uid: d['uid'] as String,
    createdAt: (d['createdAt'] as Timestamp).toDate(),
    cancelledAt: (d['cancelledAt'] as Timestamp?)?.toDate(),
    source: switch (d['source']) {
      'app' => RsvpSource.app,
      'coach-added' => RsvpSource.coachAdded,
      _ => throw const FormatException('Unknown RSVP source'),
    },
  );
}

class CheckInRecord {
  const CheckInRecord({
    required this.eventId,
    required this.uid,
    required this.scannedAt,
    required this.method,
    required this.status,
    required this.lat,
    required this.lng,
    required this.distanceM,
    required this.walkIn,
    required this.corrections,
    this.confirmedBy,
  });
  final String eventId, uid;
  final DateTime scannedAt;
  final CheckInMethod method;
  final CheckInStatus status;
  final double? lat, lng, distanceM;
  final bool walkIn;
  final String? confirmedBy;
  final List<Map<String, dynamic>> corrections;
  factory CheckInRecord.fromMap(Map<String, dynamic> d) => CheckInRecord(
    eventId: d['eventId'] as String,
    uid: d['uid'] as String,
    scannedAt: (d['scannedAt'] as Timestamp).toDate(),
    method: CheckInMethod.values.byName(d['method'] as String),
    status: CheckInStatus.values.byName(d['status'] as String),
    lat: (d['lat'] as num?)?.toDouble(),
    lng: (d['lng'] as num?)?.toDouble(),
    distanceM: (d['distanceM'] as num?)?.toDouble(),
    walkIn: d['walkIn'] as bool,
    confirmedBy: d['confirmedBy'] as String?,
    corrections: (d['corrections'] as List)
        .map((e) => Map<String, dynamic>.from(e as Map))
        .toList(),
  );
}
