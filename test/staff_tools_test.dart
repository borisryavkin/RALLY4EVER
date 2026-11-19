import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:rally4ever/participant/app.dart';
import 'package:rally4ever/participant/coach_console.dart';
import 'package:rally4ever/participant/catalogue_admin.dart';
import 'package:timezone/data/latest.dart' as tz;
import 'package:rally4ever/participant/repository.dart';
import 'package:rally4ever/participant/theme.dart';

import 'support/fake_participant.dart';

class StaffRepo extends FakeParticipantRepository {
  StaffRepo(String role) {
    profile['role'] = role;
    profile['coachEnabled'] = role == 'coach';
    claimRole = role;
    claimRoles = {'participant', role};
    uid = role == 'coach' ? 'coach-1' : 'participant-1';
    events.first['status'] = 'published';
  }
  @override
  Future<Record> call(String name, Record data) async {
    calls.add(name);
    if (name == 'listStaffSessions') {
      return {'events': events, 'limited': false};
    }
    if (name == 'getEventConsole') {
      return {
        'event': events.first,
        'roster': [
          {
            'uid': 'member',
            'firstName': 'Alex',
            'lastName': 'Lee',
            'email': 'alex@example.test',
            'countedIn': true,
            'checkinStatus': 'pending',
            'scannedAt': now().toIso8601String(),
            'distanceM': 42,
            'walkIn': false,
          },
        ],
        'limited': false,
      };
    }
    if (name == 'rotateEventSecret') {
      return {
        'url': 'https://rally4ever.org/c/EVENT-1?k=valid-secret',
        'generation': 1,
        'expiresAt': now().add(const Duration(minutes: 5)).toIso8601String(),
      };
    }
    if (name == 'coachDecision') return {'status': 'confirmed'};
    return super.call(name, data);
  }
}

void main() {
  setUpAll(tz.initializeTimeZones);
  for (final role in ['participant', 'coach', 'admin']) {
    testWidgets('Me exposes only authorized tools for $role', (tester) async {
      final repo = StaffRepo(role);
      await tester.pumpWidget(
        ParticipantApp(
          repository: repo,
          initialPage: 'profile',
          cameraEnabled: false,
          mapTilesEnabled: false,
        ),
      );
      await tester.pumpAndSettle();
      expect(
        find.widgetWithText(FilledButton, 'Admin'),
        role == 'admin' ? findsOneWidget : findsNothing,
      );
      expect(
        find.widgetWithText(OutlinedButton, 'Coach tools'),
        role == 'participant' ? findsNothing : findsOneWidget,
      );
      if (role == 'admin') {
        await tester.tap(find.widgetWithText(FilledButton, 'Admin'));
        await tester.pumpAndSettle();
        expect(find.text('Programs'), findsOneWidget);
        expect(find.text('Sessions'), findsOneWidget);
        expect(find.text('Users & coach assignment'), findsOneWidget);
      }
      await tester.pumpWidget(const SizedBox());
      repo.dispose();
    });
  }
  testWidgets(
    'sign-in waits for the profile stream before choosing onboarding',
    (tester) async {
      final repo = StaffRepo('admin');
      repo.ready = false;
      final savedProfile = repo.profile;
      repo.profile = {};
      await tester.pumpWidget(
        ParticipantApp(
          repository: repo,
          initialPage: 'account',
          cameraEnabled: false,
          mapTilesEnabled: false,
        ),
      );
      repo.notifyListeners();
      await tester.pump();
      repo.profile = savedProfile;
      repo.ready = true;
      repo.notifyListeners();
      await tester.pumpAndSettle();
      expect(find.text('Tell us a little about you'), findsNothing);
      expect(find.text('Admin view'), findsOneWidget);
      await tester.pumpWidget(const SizedBox());
      repo.dispose();
    },
  );
  testWidgets(
    'legacy session editor prefills venue and exposes per-session coaches',
    (tester) async {
      final repo = StaffRepo('admin');
      final session = {
        ...repo.events.first,
        'id': 'legacy',
        'startsAt': repo.now().add(const Duration(days: 1)),
        'endsAt': repo.now().add(const Duration(days: 1, hours: 1)),
      };
      await tester.pumpWidget(
        MaterialApp(
          theme: rallyTheme(),
          home: SessionEditor(
            repository: repo,
            program: {...session, 'id': null},
            session: session,
          ),
        ),
      );
      await tester.pumpAndSettle();
      expect(find.text('Edit / cancel session'), findsOneWidget);
      expect(find.text('Waverley Park, Bondi Junction'), findsOneWidget);
      expect(find.textContaining('Times use Australia/Sydney'), findsOneWidget);
      expect(tester.takeException(), isNull);
      await tester.pumpWidget(const SizedBox());
      repo.dispose();
    },
  );
  testWidgets(
    'admin QR console separates intent and attendance and hides on revocation',
    (tester) async {
      final repo = StaffRepo('admin');
      await tester.pumpWidget(
        MaterialApp(
          theme: rallyTheme(),
          home: EventConsoleScreen(repository: repo, eventId: 'event-1'),
        ),
      );
      await tester.pumpAndSettle();
      expect(find.byKey(const Key('event-qr')), findsOneWidget);
      expect(
        find.text('1 counted in · 1 checked in · 0 confirmed'),
        findsOneWidget,
      );
      await tester.scrollUntilVisible(find.text('Confirm arrival'), 250);
      expect(find.textContaining('42 m from venue'), findsOneWidget);
      await tester.tap(find.text('Confirm arrival'));
      await tester.pumpAndSettle();
      expect(repo.calls, contains('coachDecision'));
      repo.profile['role'] = 'participant';
      repo.claimRole = 'participant';
      repo.claimRoles = {'participant'};
      repo.notifyListeners();
      await tester.pump();
      expect(find.byKey(const Key('event-qr')), findsNothing);
      expect(
        find.text('Staff access is unavailable for this session.'),
        findsOneWidget,
      );
      await tester.pumpWidget(const SizedBox());
      repo.dispose();
    },
  );
  testWidgets('coach cannot open unassigned session or request its QR', (
    tester,
  ) async {
    final repo = StaffRepo('coach');
    await tester.pumpWidget(
      MaterialApp(
        home: EventConsoleScreen(repository: repo, eventId: 'event-2'),
      ),
    );
    await tester.pumpAndSettle();
    expect(repo.calls, isNot(contains('getEventConsole')));
    expect(find.byKey(const Key('event-qr')), findsNothing);
    await tester.pumpWidget(const SizedBox());
    repo.dispose();
  });
}
