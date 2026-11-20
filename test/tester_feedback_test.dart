import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:rally4ever/participant/app.dart';
import 'package:rally4ever/participant/repository.dart';

import 'support/fake_participant.dart';

/// A tall viewport so content well down a long scrollable screen is within
/// Sliver's cacheExtent and actually mounts (plain ListView(children:) is
/// still Sliver-backed and lazy by viewport, not just ListView.builder).
void setTallView(WidgetTester tester) {
  tester.view.physicalSize = const Size(390, 2600);
  tester.view.devicePixelRatio = 1;
  addTearDown(tester.view.resetPhysicalSize);
  addTearDown(tester.view.resetDevicePixelRatio);
}

/// Never actually verifies -- lets a test exercise the "I've verified" tap
/// while the email genuinely isn't confirmed yet.
class StillUnverifiedRepo extends FakeParticipantRepository {
  StillUnverifiedRepo() : super(authenticated: false);
  @override
  Future<void> refreshVerification() async {}
}

Record _program({
  String id = 'bondi',
  String suburb = 'Bondi Junction',
  String postcode = '2022',
}) => {
  'id': id,
  'name': '$suburb tennis',
  'status': 'active',
  'sport': 'tennis',
  'venue': {
    'name': 'Community courts',
    'suburb': suburb,
    'postcode': postcode,
    'state': 'NSW',
    'lat': -33.8926,
    'lng': 151.2511,
  },
  'scheduleText': 'Tuesdays',
  'timezone': 'Australia/Sydney',
  'coachUids': <String>[],
  'coachNames': <String>[],
  'registrationStatus': 'open',
};

Record _session(
  String id,
  DateTime now, {
  int? capacity,
  int bookedCount = 0,
  String registrationStatus = 'open',
  String programId = 'bondi',
}) => {
  'id': id,
  'eventId': id,
  'programId': programId,
  'catalogueManaged': true,
  'name': 'Bondi Junction tennis',
  'sport': 'tennis',
  'status': 'published',
  'startsAt': now.add(const Duration(hours: 1)),
  'endsAt': now.add(const Duration(hours: 2)),
  'venue': {'name': 'Community courts', 'lat': -33.8926, 'lng': 151.2511},
  'coachUids': <String>[],
  'requiredFormIds': <String>[],
  'capacity': capacity,
  'bookedCount': bookedCount,
  'registrationStatus': registrationStatus,
};

void main() {
  group('item 1: sign-up and email verification', () {
    testWidgets(
      'a first-time device defaults to Create account; a returning device defaults to Welcome back; each links to the other',
      (tester) async {
        setTallView(tester);
        final firstTime = FakeParticipantRepository(authenticated: false)
          ..hasSignedInBefore = false;
        await tester.pumpWidget(
          ParticipantApp(
            repository: firstTime,
            initialPage: 'account',
            cameraEnabled: false,
          ),
        );
        await tester.pumpAndSettle();
        expect(find.text('Join the\ncommunity'), findsOneWidget);
        expect(find.text('Already a member? Sign in'), findsOneWidget);
        await tester.tap(find.byKey(const Key('toggle-signup')));
        await tester.pumpAndSettle();
        expect(find.text('Welcome\nback'), findsOneWidget);
        expect(find.text('New here? Create an account'), findsOneWidget);
        await tester.pumpWidget(const SizedBox());
        firstTime.dispose();

        final returning = FakeParticipantRepository(authenticated: false)
          ..hasSignedInBefore = true;
        await tester.pumpWidget(
          ParticipantApp(
            repository: returning,
            initialPage: 'account',
            cameraEnabled: false,
          ),
        );
        await tester.pumpAndSettle();
        expect(find.text('Welcome\nback'), findsOneWidget);
        await tester.pumpWidget(const SizedBox());
        returning.dispose();
      },
    );

    testWidgets(
      'removed strings never appear on the account screen',
      (tester) async {
        final repo = FakeParticipantRepository(authenticated: false);
        await tester.pumpWidget(
          ParticipantApp(
            repository: repo,
            initialPage: 'account',
            cameraEnabled: false,
          ),
        );
        await tester.pumpAndSettle();
        expect(
          find.textContaining('Coach access is approved by your admin'),
          findsNothing,
        );
        expect(
          find.textContaining('Coaches use their pre-created account'),
          findsNothing,
        );
      },
    );

    testWidgets(
      'after signing up, a prominent panel offers Open email app / Resend email / I\'ve verified, with a friendly "not yet" hint',
      (tester) async {
        setTallView(tester);
        final repo = StillUnverifiedRepo();
        await tester.pumpWidget(
          ParticipantApp(
            repository: repo,
            initialPage: 'account',
            cameraEnabled: false,
          ),
        );
        await tester.pumpAndSettle();
        // This repo defaults to "Welcome back" (a returning device) --
        // switch to "Create account" so the button actually calls signUp.
        await tester.tap(find.byKey(const Key('toggle-signup')));
        await tester.pumpAndSettle();
        await tester.enterText(find.byKey(const Key('email')), 'new@example.test');
        await tester.enterText(find.byKey(const Key('password')), 'Test-password-1');
        await tester.tap(find.byKey(const Key('authenticate')));
        await tester.pumpAndSettle();
        expect(find.text('Check your inbox'), findsOneWidget);
        expect(find.textContaining('new@example.test'), findsOneWidget);
        expect(find.byKey(const Key('open-email-app')), findsOneWidget);
        expect(find.byKey(const Key('resend-verification')), findsOneWidget);
        expect(find.byKey(const Key('verified-email')), findsOneWidget);
        // Never shown next to "Create account" -- only once an account
        // exists and is pending verification.
        expect(find.text('Create account'), findsNothing);

        await tester.tap(find.byKey(const Key('verified-email')));
        await tester.pumpAndSettle();
        expect(
          find.text("We can't see it yet. Check your inbox and spam folder."),
          findsOneWidget,
        );

        await tester.tap(find.byKey(const Key('resend-verification')));
        await tester.pumpAndSettle();
        expect(find.textContaining('Resend in'), findsOneWidget);
      },
    );
  });

  group('item 2: check in without an app account', () {
    testWidgets(
      'Scan QR code is the first and main action; pasting a link is a hidden secondary option',
      (tester) async {
        final repo = FakeParticipantRepository(authenticated: false);
        await tester.pumpWidget(
          ParticipantApp(
            repository: repo,
            initialPage: 'noapp',
            cameraEnabled: false,
          ),
        );
        await tester.pumpAndSettle();
        expect(find.byKey(const Key('start-scan')), findsOneWidget);
        expect(find.text('Scan QR code'), findsOneWidget);
        expect(find.byKey(const Key('toggle-paste-link')), findsOneWidget);
        expect(find.byKey(const Key('noapp-qr')), findsNothing);
        await tester.tap(find.byKey(const Key('start-scan')));
        await tester.pumpAndSettle();
        // Tapping it is what asks for camera access -- not a startup
        // permission prompt before the user has engaged with the feature.
        expect(find.byKey(const Key('start-scan')), findsNothing);
        await tester.tap(find.byKey(const Key('toggle-paste-link')));
        await tester.pumpAndSettle();
        expect(find.byKey(const Key('noapp-qr')), findsOneWidget);
      },
    );

    testWidgets(
      'an invalid session code shows a friendly message, never the FormatException class name',
      (tester) async {
        setTallView(tester);
        final repo = FakeParticipantRepository(authenticated: false);
        await tester.pumpWidget(
          ParticipantApp(
            repository: repo,
            initialPage: 'noapp',
            cameraEnabled: false,
          ),
        );
        await tester.pumpAndSettle();
        await tester.tap(find.byKey(const Key('toggle-paste-link')));
        await tester.pumpAndSettle();
        await tester.enterText(
          find.byKey(const Key('noapp-qr')),
          'not a real link',
        );
        await tester.tap(find.byKey(const Key('noapp-use-code')));
        await tester.pumpAndSettle();
        expect(
          find.text(
            "That doesn't look like a Rally4Ever session code. Ask your coach to show the current QR code.",
          ),
          findsOneWidget,
        );
        expect(find.textContaining('FormatException'), findsNothing);
      },
    );
  });

  group('item 3: location search', () {
    testWidgets(
      'empty search shows Use my current location and Recent above the full, always-visible list',
      (tester) async {
        final repo = FakeParticipantRepository()
          ..programs = [
            _program(id: 'bondi', suburb: 'Bondi Junction', postcode: '2022'),
            _program(id: 'epping', suburb: 'Epping', postcode: '2121'),
          ];
        repo.recordLocationSearch('Parramatta 2150');
        await tester.pumpWidget(
          ParticipantApp(
            repository: repo,
            initialPage: 'location',
            cameraEnabled: false,
            mapTilesEnabled: false,
          ),
        );
        await tester.pumpAndSettle();
        expect(find.text('Choose location'), findsOneWidget);
        expect(find.byKey(const Key('use-my-location')), findsOneWidget);
        expect(find.text('Recent'), findsOneWidget);
        expect(find.text('Parramatta 2150'), findsOneWidget);
        // The recent entry is additive -- the full suburb list is still
        // there underneath it, not replaced.
        expect(find.text('Bondi Junction 2022'), findsOneWidget);
        expect(find.text('Epping 2121'), findsOneWidget);

        await tester.tap(find.byKey(const Key('clear-recent-locations')));
        await tester.pumpAndSettle();
        expect(find.text('Recent'), findsNothing);
        expect(find.text('Bondi Junction 2022'), findsOneWidget);
      },
    );

    testWidgets(
      'typing filters the full list by suburb or postcode, with a no-results message',
      (tester) async {
        final repo = FakeParticipantRepository()
          ..programs = [
            _program(id: 'bondi', suburb: 'Bondi Junction', postcode: '2022'),
            _program(id: 'epping', suburb: 'Epping', postcode: '2121'),
          ];
        await tester.pumpWidget(
          ParticipantApp(
            repository: repo,
            initialPage: 'location',
            cameraEnabled: false,
            mapTilesEnabled: false,
          ),
        );
        await tester.pumpAndSettle();
        await tester.enterText(
          find.byKey(const Key('location-search')),
          '2121',
        );
        await tester.pumpAndSettle();
        expect(find.text('Epping 2121'), findsOneWidget);
        expect(find.text('Bondi Junction 2022'), findsNothing);
        // Typing hides the empty-search-only shortcuts too.
        expect(find.byKey(const Key('use-my-location')), findsNothing);

        await tester.enterText(
          find.byKey(const Key('location-search')),
          'nowhere',
        );
        await tester.pumpAndSettle();
        expect(find.text('No locations match that search.'), findsOneWidget);
      },
    );
  });

  group('item 5: full and closed sessions', () {
    testWidgets(
      'full and bookings-closed sessions render muted with a distinct tag, cancellable not reservable',
      (tester) async {
        final now = DateTime.now();
        final repo = FakeParticipantRepository()
          ..catalogueReady = true
          ..programs = [_program()]
          ..events = [
            _session('full', now, capacity: 10, bookedCount: 10),
            _session(
              'closed',
              now.add(const Duration(hours: 3)),
              registrationStatus: 'closed',
            ),
          ];
        await tester.pumpWidget(
          ParticipantApp(
            repository: repo,
            initialPage: 'home',
            cameraEnabled: false,
            mapTilesEnabled: false,
          ),
        );
        await tester.pumpAndSettle();
        expect(find.text('Full'), findsOneWidget);
        expect(find.text('Bookings closed'), findsOneWidget);
        // Both are visible (tappable) list entries, not hidden.
        expect(find.byKey(const Key('event-full')), findsOneWidget);
        expect(find.byKey(const Key('event-closed')), findsOneWidget);
      },
    );

    testWidgets(
      'a program with many dates shows only the next few with an "n more dates" expander',
      (tester) async {
        setTallView(tester);
        final now = DateTime.now();
        final repo = FakeParticipantRepository()
          ..catalogueReady = true
          ..programs = [_program()]
          ..events = [
            for (var i = 0; i < 5; i++)
              _session(
                'session-$i',
                now.add(Duration(hours: i + 1, minutes: i)),
              ),
          ];
        await tester.pumpWidget(
          ParticipantApp(
            repository: repo,
            initialPage: 'home',
            cameraEnabled: false,
            mapTilesEnabled: false,
          ),
        );
        await tester.pumpAndSettle();
        expect(find.byKey(const Key('event-session-0')), findsOneWidget);
        expect(find.byKey(const Key('event-session-2')), findsOneWidget);
        expect(find.byKey(const Key('event-session-4')), findsNothing);
        expect(find.text('2 more dates'), findsOneWidget);

        await tester.tap(find.text('2 more dates'));
        await tester.pumpAndSettle();
        expect(find.byKey(const Key('event-session-4')), findsOneWidget);
        expect(find.text('2 more dates'), findsNothing);
      },
    );
  });
}
