import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:rally4ever/data/emulator_backend.dart';
import 'package:rally4ever/models/attendance_models.dart';

void main() {
  test('normalize email consistently across coaches and login', () {
    expect(normalizeEmail('  Member1@Example.TEST  '), 'member1@example.test');
    expect(attendanceId('event-1', 'member-1'), 'event-1_member-1');
    expect(consentId('member-1', 'waiver'), 'member-1_waiver');
  });
  test(
    'protected role overrides stale claims and unknown roles fail closed',
    () {
      expect(
        AppRole.resolve(profileRole: 'participant', claimRole: 'admin'),
        AppRole.participant,
      );
      expect(AppRole.resolve(claimRole: 'coach'), AppRole.coach);
      expect(
        AppRole.resolve(profileRole: 'unknown', claimRole: 'admin'),
        AppRole.participant,
      );
      expect(AppRole.resolve(), AppRole.participant);
    },
  );
  test(
    'emulator config rejects production and requires explicit opt in',
    () async {
      for (final host in ['localhost', '127.0.0.1', '10.0.2.2']) {
        expect(EmulatorBackend.validateHost(host), host);
      }
      expect(
        () => EmulatorBackend.validateHost('firestore.googleapis.com'),
        throwsArgumentError,
      );
      await expectLater(
        EmulatorBackend.connect(enabled: false),
        throwsStateError,
      );
    },
  );
  test(
    'intent remains independent from pending/confirmed/rejected attendance',
    () {
      final now = Timestamp.fromDate(DateTime.utc(2026, 11, 17));
      final intent = RsvpRecord.fromMap({
        'uid': 'p1',
        'eventId': 'e1',
        'createdAt': now,
        'cancelledAt': null,
        'source': 'coach-added',
      });
      expect(intent.countedIn, true);
      expect(intent.source, RsvpSource.coachAdded);
      for (final status in CheckInStatus.values) {
        final attendance = CheckInRecord.fromMap({
          'uid': 'p1',
          'eventId': 'e1',
          'scannedAt': now,
          'status': status.name,
          'method': 'camera',
          'lat': -33.89,
          'lng': 151.25,
          'distanceM': 20,
          'walkIn': false,
          'corrections': [],
          'confirmedBy': null,
        });
        expect(attendance.status, status);
        expect(intent.countedIn, true);
      }
    },
  );
  test('events retain actual instance times and coach assignments', () {
    final start = DateTime.utc(2026, 11, 17, 7, 30);
    final event = RallyEvent.fromMap('e1', {
      'code': 'E1',
      'name': 'Rally',
      'startsAt': Timestamp.fromDate(start),
      'endsAt': Timestamp.fromDate(start.add(const Duration(hours: 1))),
      'timezone': 'Australia/Sydney',
      'coachUids': ['coach-2'],
      'venue': {'lat': -33.89, 'lng': 151.25},
      'geofenceRadiusM': 150,
      'requiredFormIds': ['conduct', 'waiver'],
    });
    expect(event.checkInOpensAt.toUtc(), DateTime.utc(2026, 11, 17, 7, 20));
    expect(event.coachUids, ['coach-2']);
    expect(event.geofenceRadiusM, 150);
  });
}
