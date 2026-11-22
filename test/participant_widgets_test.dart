import 'package:cached_network_image/cached_network_image.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:rally4ever/participant/app.dart';
import 'package:rally4ever/participant/repository.dart';
import 'package:timezone/data/latest.dart' as tz;

import 'support/fake_participant.dart';

void main() {
  setUpAll(() async {
    tz.initializeTimeZones();
    await (FontLoader(
      'MaterialIcons',
    )..addFont(rootBundle.load('fonts/MaterialIcons-Regular.otf'))).load();
    for (final name in ['Inter']) {
      final loader = FontLoader(name)
        ..addFont(rootBundle.load('assets/fonts/$name.ttf'));
      await loader.load();
    }
    await (FontLoader('Jellee')..addFont(
          rootBundle.load('assets/fonts/Jellee_1223/TTF/Jellee-Bold.ttf'),
        ))
        .load();
  });
  Future<void> show(
    WidgetTester tester,
    FakeParticipantRepository repo,
    String page, {
    String event = 'event-1',
  }) async {
    tester.view.physicalSize = const Size(390, 844);
    tester.view.devicePixelRatio = 1;
    addTearDown(tester.view.resetPhysicalSize);
    addTearDown(tester.view.resetDevicePixelRatio);
    await tester.pumpWidget(
      RepaintBoundary(
        key: const Key('capture'),
        child: ParticipantApp(
          repository: repo,
          initialPage: page,
          initialEventId: event,
          cameraEnabled: false,
          mapTilesEnabled: false,
        ),
      ),
    );
    await tester.pumpAndSettle();
  }

  testWidgets(
    'valid app link waits for login and opens QR flow without attendance',
    (tester) async {
      final repo = FakeParticipantRepository(authenticated: false);
      await show(tester, repo, 'signin');
      final link = 'https://rally4ever.org/c/EVENT-1?k=${'a' * 43}';
      await tester.binding.defaultBinaryMessenger.handlePlatformMessage(
        'flutter/navigation',
        const JSONMethodCodec().encodeMethodCall(
          MethodCall('pushRouteInformation', {'location': link}),
        ),
        (_) {},
      );
      await tester.pumpAndSettle();
      expect(find.text('Scan coach’s QR'), findsNothing);
      repo.uid = 'participant-1';
      repo.ready = true;
      repo.notifyListeners();
      await tester.pumpAndSettle();
      expect(find.widgetWithText(TextField, link), findsOneWidget);
      expect(repo.checkins.where((c) => c['eventId'] == 'event-1'), isEmpty);
      await tester.pumpWidget(const SizedBox.shrink());
    },
  );

  testWidgets(
    'forgot password always shows the same neutral confirmation and a resend cooldown',
    (tester) async {
      final repo = FakeParticipantRepository(authenticated: false);
      await show(tester, repo, 'signin');
      expect(find.text('Email me a one-time sign-in link'), findsNothing);
      expect(find.text('I have an email link'), findsNothing);
      await tester.tap(find.byKey(const Key('forgot-password')));
      await tester.pumpAndSettle();
      expect(find.text('Reset your\npassword'), findsOneWidget);
      await tester.enterText(
        find.byKey(const Key('reset-email')),
        'someone@example.test',
      );
      await tester.tap(find.byKey(const Key('send-reset')));
      await tester.pumpAndSettle();
      expect(repo.calls.contains('sendPasswordReset'), true);
      expect(find.byKey(const Key('reset-sent')), findsOneWidget);
      expect(
        find.text(
          "If an account exists for that email, we've sent a link to "
          'reset the password. Check your inbox and spam folder.',
        ),
        findsOneWidget,
      );
      expect(find.text('Resend in 60s'), findsOneWidget);
      await tester.pumpWidget(const SizedBox.shrink());
      repo.dispose();
    },
  );
  testWidgets(
    'forgot password shows a friendly message for rate limiting, not a raw error',
    (tester) async {
      final repo = FakeParticipantRepository(authenticated: false);
      repo.passwordResetRateLimited = true;
      await show(tester, repo, 'signin');
      await tester.tap(find.byKey(const Key('forgot-password')));
      await tester.pumpAndSettle();
      await tester.enterText(
        find.byKey(const Key('reset-email')),
        'someone@example.test',
      );
      await tester.tap(find.byKey(const Key('send-reset')));
      await tester.pumpAndSettle();
      expect(find.byKey(const Key('reset-sent')), findsNothing);
      expect(
        find.text('Too many attempts. Wait a few minutes and try again.'),
        findsOneWidget,
      );
      await tester.pumpWidget(const SizedBox.shrink());
      repo.dispose();
    },
  );
  testWidgets('cold-start relative QR link opens the same strict scan flow', (
    tester,
  ) async {
    final route = '/c/EVENT-1?k=${'a' * 43}';
    tester.binding.platformDispatcher.defaultRouteNameTestValue = route;
    addTearDown(
      tester.binding.platformDispatcher.clearDefaultRouteNameTestValue,
    );
    final repo = FakeParticipantRepository();
    await show(tester, repo, 'home');
    expect(
      find.widgetWithText(TextField, 'https://rally4ever.org$route'),
      findsOneWidget,
    );
    expect(repo.checkins.where((c) => c['eventId'] == 'event-1'), isEmpty);
    await tester.pumpWidget(const SizedBox.shrink());
  });

  testWidgets('unrelated app links cannot enter check-in', (tester) async {
    final repo = FakeParticipantRepository();
    await show(tester, repo, 'home');
    await tester.binding.defaultBinaryMessenger.handlePlatformMessage(
      'flutter/navigation',
      const JSONMethodCodec().encodeMethodCall(
        MethodCall('pushRouteInformation', {
          'location': 'https://evil.example/c/EVENT-1?k=${'a' * 43}',
        }),
      ),
      (_) {},
    );
    await tester.pumpAndSettle();
    expect(find.text('Play near you'), findsOneWidget);
    expect(repo.checkins.where((c) => c['eventId'] == 'event-1'), isEmpty);
    await tester.pumpWidget(const SizedBox.shrink());
  });

  final screens = [
    ('S01-intro-program', 'welcome1'),
    ('S02-intro-people', 'welcome2'),
    ('S03-intro-wellbeing', 'welcome3'),
    ('S04-account', 'signup'),
    ('S05-profile-basics', 'profile1'),
    ('S06-profile-inclusion', 'profile2'),
    ('S07-profile-research', 'profile3'),
    ('S08-profile-wellbeing', 'profile4'),
    ('S09-profile-consent', 'profile5'),
    ('S10-home-counted-in', 'home'),
    ('S11-map', 'map'),
    ('S12-session', 'session'),
    ('S13-counted-in-people', 'people'),
    ('S14-checkin-not-open', 'checkin'),
    ('S15-qr-scan', 'scan'),
    ('S16-before-session', 'details'),
    ('S17-current-agreements', 'agreements'),
    ('S18-waiting', 'waiting'),
    ('S19-confirmed', 'confirmed'),
    ('S20-no-app', 'noapp'),
    ('S21-feedback-reminder', 'feedbackReminder'),
    ('S22-feedback', 'feedback'),
    ('S23-profile', 'profile'),
    ('S24-help', 'help'),
  ];
  for (final screen in screens) {
    testWidgets('renders and captures ${screen.$1}', (tester) async {
      final repo = FakeParticipantRepository(
        attendance: screen.$2 == 'waiting'
            ? 'pending'
            : screen.$2 == 'confirmed'
            ? 'confirmed'
            : null,
      );
      if (screen.$1.startsWith('S14')) {
        repo.clock = DateTime.utc(2026, 11, 17, 7);
      }
      if (screen.$2 == 'agreements') repo.consents = [];
      await show(
        tester,
        repo,
        screen.$2,
        event: ['feedback', 'feedbackReminder'].contains(screen.$2)
            ? 'event-3'
            : 'event-1',
      );
      expect(tester.takeException(), isNull);
      await expectLater(
        find.byKey(const Key('capture')),
        matchesGoldenFile('../docs/screenshots/participant/${screen.$1}.png'),
      );
      await tester.pumpWidget(const SizedBox());
      repo.dispose();
    });
  }
  for (final status in ['pending', 'confirmed', 'rejected']) {
    testWidgets('home/attendance show $status independently of intent', (
      tester,
    ) async {
      final repo = FakeParticipantRepository(
        counted: false,
        attendance: status,
      );
      await show(tester, repo, 'waiting');
      expect(
        find.text(
          status == 'confirmed'
              ? 'Confirmed'
              : status == 'pending'
              ? 'Pending confirmation'
              : 'Needs review',
        ),
        findsOneWidget,
      );
      expect(repo.countedIn('event-1'), false);
      await tester.pumpWidget(const SizedBox());
      repo.dispose();
    });
  }
  testWidgets('Count me in writes intent only', (tester) async {
    final repo = FakeParticipantRepository(counted: false);
    await show(tester, repo, 'session');
    await tester.tap(find.byKey(const Key('count-me-in')));
    await tester.pumpAndSettle();
    expect(repo.countedIn('event-1'), true);
    expect(repo.checkin('event-1'), null);
    expect(repo.calls.contains('checkIn'), false);
    await tester.pumpWidget(const SizedBox());
    repo.dispose();
  });
  testWidgets(
    'arbitrary QR is rejected before location or callable; valid scan waits then confirms',
    (tester) async {
      final repo = FakeParticipantRepository();
      await show(tester, repo, 'scan');
      await tester.enterText(
        find.byKey(const Key('qr-link')),
        'https://example.org/anything',
      );
      await tester.tap(find.byKey(const Key('use-qr')));
      await tester.pumpAndSettle();
      expect(find.byKey(const Key('error-banner')), findsOneWidget);
      expect(repo.calls.contains('checkIn'), false);
      await tester.enterText(
        find.byKey(const Key('qr-link')),
        'https://rally4ever.org/c/EVENT-1?k=${'A' * 43}',
      );
      await tester.tap(find.byKey(const Key('use-qr')));
      await tester.pumpAndSettle();
      expect(find.text('Pending confirmation'), findsOneWidget);
      repo.confirm();
      await tester.pumpAndSettle();
      expect(find.text('Confirmed'), findsOneWidget);
      await tester.pumpWidget(const SizedBox());
      repo.dispose();
    },
  );
  testWidgets(
    'before-session details prefill and forms only reappear when version changes',
    (tester) async {
      final repo = FakeParticipantRepository();
      await show(tester, repo, 'details');
      expect(find.widgetWithText(TextField, 'Priya'), findsOneWidget);
      expect(repo.missingForms(repo.events.first), isEmpty);
      repo.forms[0]['version'] = 2;
      expect(repo.missingForms(repo.events.first).length, 1);
      await tester.pumpWidget(const SizedBox());
      repo.dispose();
    },
  );
  testWidgets('early/late states disable scanning', (tester) async {
    final repo = FakeParticipantRepository();
    repo.events[0]['startsAt'] = repo.now().add(const Duration(hours: 1));
    await show(tester, repo, 'checkin');
    expect(
      tester
          .widget<FilledButton>(find.byKey(const Key('start-scan')))
          .onPressed,
      isNull,
    );
    await tester.pumpWidget(const SizedBox());
    repo.events[0]['startsAt'] = repo.now().subtract(const Duration(hours: 2));
    repo.events[0]['endsAt'] = repo.now().subtract(const Duration(hours: 1));
    await show(tester, repo, 'checkin');
    expect(find.text('Check-in has\nclosed'), findsOneWidget);
    expect(
      tester
          .widget<FilledButton>(find.byKey(const Key('start-scan')))
          .onPressed,
      isNull,
    );
    await tester.pumpWidget(const SizedBox());
    repo.dispose();
  });
  test(
    'strict deep-link format rejects host spoofing, extra params and fragments',
    () {
      final valid = 'https://rally4ever.org/c/EVENT-1?k=${'A' * 43}';
      expect(CheckInLink.parse(valid).eventCode, 'EVENT-1');
      for (final raw in [
        'anything',
        valid.replaceFirst('https', 'http'),
        valid.replaceFirst('rally4ever.org', 'rally4ever.org.evil.test'),
        '$valid&uid=someone',
        '$valid#fragment',
        valid.replaceFirst('/c/', '/other/'),
      ]) {
        expect(() => CheckInLink.parse(raw), throwsFormatException);
      }
    },
  );
  testWidgets(
    'Google Workspace without claim stays participant and shows no coach-access banner',
    (tester) async {
      final repo = FakeParticipantRepository(authenticated: false);
      await show(tester, repo, 'signin');
      await tester.tap(find.byKey(const Key('google-sign-in')));
      await tester.pumpAndSettle();
      expect(repo.googleUser, true);
      expect(repo.role, 'participant');
      expect(
        find.text(
          'Ask your admin for coach access. Your participant profile is ready.',
        ),
        findsNothing,
      );
      expect(find.text('Refresh access'), findsNothing);
      expect(find.text('Coach view'), findsNothing);
      await tester.pumpWidget(const SizedBox());
      repo.dispose();
    },
  );
  testWidgets('coach/admin still get their view button with the banner gone', (
    tester,
  ) async {
    final repo = FakeParticipantRepository();
    repo.claimRole = 'coach';
    repo.claimRoles = {'participant', 'coach'};
    repo.profile['role'] = 'coach';
    repo.profile['coachEnabled'] = true;
    await show(tester, repo, 'home');
    expect(
      find.text(
        'Ask your admin for coach access. Your participant profile is ready.',
      ),
      findsNothing,
    );
    expect(find.text('Coach view'), findsOneWidget);
    await tester.pumpWidget(const SizedBox());
    repo.dispose();
  });
  testWidgets('Admin view never appears on Play, even for an admin account', (
    tester,
  ) async {
    final repo = FakeParticipantRepository();
    repo.claimRole = 'admin';
    repo.claimRoles = {'participant', 'admin'};
    repo.profile['role'] = 'admin';
    await show(tester, repo, 'home');
    expect(find.text('Play near you'), findsOneWidget);
    expect(find.text('Admin view'), findsNothing);
    expect(find.text('Admin'), findsNothing);
    await tester.pumpWidget(const SizedBox());
    repo.dispose();
  });
  testWidgets('Admin access is still reachable from Me for an admin account', (
    tester,
  ) async {
    final repo = FakeParticipantRepository();
    repo.claimRole = 'admin';
    repo.claimRoles = {'participant', 'admin'};
    repo.profile['role'] = 'admin';
    await show(tester, repo, 'profile');
    expect(find.widgetWithText(FilledButton, 'Admin'), findsOneWidget);
    await tester.pumpWidget(const SizedBox());
    repo.dispose();
  });
  testWidgets(
    'returning to the foreground refreshes role/access quietly, with no button press',
    (tester) async {
      final repo = FakeParticipantRepository();
      await show(tester, repo, 'home');
      expect(repo.calls.contains('refreshAccess'), false);
      final state =
          tester.state(find.byType(ParticipantApp)) as WidgetsBindingObserver;
      state.didChangeAppLifecycleState(AppLifecycleState.paused);
      state.didChangeAppLifecycleState(AppLifecycleState.resumed);
      await tester.pumpAndSettle();
      expect(repo.calls.contains('refreshAccess'), true);
      await tester.pumpWidget(const SizedBox());
      repo.dispose();
    },
  );
  testWidgets(
    'one profile switches views and revocation immediately removes coach view',
    (tester) async {
      final repo = FakeParticipantRepository();
      repo.claimRole = 'coach';
      repo.claimRoles = {'participant', 'coach'};
      repo.profile['role'] = 'coach';
      repo.profile['coachEnabled'] = true;
      final originalUid = repo.uid;
      await show(tester, repo, 'home');
      await tester.tap(find.text('Coach view'));
      await tester.pumpAndSettle();
      expect(find.text('Switch to participant view'), findsOneWidget);
      expect(repo.uid, originalUid);
      await expectLater(
        find.byKey(const Key('capture')),
        matchesGoldenFile('../docs/screenshots/participant/A02-coach-view.png'),
      );
      await tester.tap(find.text('Switch to participant view'));
      await tester.pumpAndSettle();
      expect(repo.countedIn('event-1'), true);
      expect(repo.uid, originalUid);
      await tester.tap(find.text('Coach view'));
      await tester.pumpAndSettle();
      repo.profile['role'] = 'participant';
      repo.profile['coachEnabled'] = false;
      repo.notifyListeners();
      await tester.pumpAndSettle();
      expect(find.text('Coach view'), findsNothing);
      expect(repo.uid, originalUid);
      expect(find.byKey(const Key('error-banner')), findsOneWidget);
      await tester.pumpWidget(const SizedBox());
      repo.dispose();
    },
  );
  testWidgets(
    'admin access console lists emails and routes audited coach role changes',
    (tester) async {
      final repo = FakeParticipantRepository();
      repo.profile['role'] = 'admin';
      repo.claimRole = 'admin';
      repo.claimRoles = {'participant', 'admin'};
      await show(tester, repo, 'adminAccess');
      expect(find.text('mei@rally4ever.org'), findsOneWidget);
      expect(
        tester.widget<SwitchListTile>(find.byType(SwitchListTile)).onChanged,
        isNull,
      );
      await expectLater(
        find.byKey(const Key('capture')),
        matchesGoldenFile(
          '../docs/screenshots/participant/A01-admin-access.png',
        ),
      );
      await tester.enterText(
        find.byKey(const Key('access-reason')),
        'Access reviewed by admin',
      );
      await tester.pump();
      await tester.ensureVisible(find.byType(SwitchListTile));
      await tester.tap(find.byType(SwitchListTile));
      await tester.pumpAndSettle();
      expect(repo.calls.contains('setUserRole'), true);
      await tester.pumpWidget(const SizedBox());
      repo.dispose();
    },
  );
  test('a protected coach field alone never enables coach UI', () {
    final repo = FakeParticipantRepository();
    repo.profile['role'] = 'coach';
    repo.profile['coachEnabled'] = true;
    expect(repo.canCoach, false);
    repo.claimRole = 'coach';
    expect(repo.canCoach, true);
    repo.profile['coachEnabled'] = false;
    expect(repo.canCoach, false);
    repo.dispose();
  });
  testWidgets(
    'server distance rejection is visible and never becomes attendance',
    (tester) async {
      final repo = FakeParticipantRepository();
      repo.checkInError = 'You are too far from the venue';
      await show(tester, repo, 'scan');
      await tester.enterText(
        find.byKey(const Key('qr-link')),
        'https://rally4ever.org/c/EVENT-1?k=${'A' * 43}',
      );
      await tester.tap(find.byKey(const Key('use-qr')));
      await tester.pumpAndSettle();
      expect(find.text('You are too far from the venue'), findsOneWidget);
      expect(repo.checkin('event-1'), isNull);
      await tester.pumpWidget(const SizedBox());
      repo.dispose();
    },
  );
  testWidgets(
    'a failed function call offers Retry, which re-runs the same action',
    (tester) async {
      final repo = FakeParticipantRepository();
      repo.checkInError = 'You are too far from the venue';
      await show(tester, repo, 'scan');
      await tester.enterText(
        find.byKey(const Key('qr-link')),
        'https://rally4ever.org/c/EVENT-1?k=${'A' * 43}',
      );
      await tester.tap(find.byKey(const Key('use-qr')));
      await tester.pumpAndSettle();
      expect(find.text('You are too far from the venue'), findsOneWidget);
      expect(find.byKey(const Key('retry-action')), findsOneWidget);
      expect(repo.checkin('event-1'), isNull);
      repo.checkInError = null;
      await tester.tap(find.byKey(const Key('retry-action')));
      await tester.pumpAndSettle();
      expect(find.text('You are too far from the venue'), findsNothing);
      expect(find.byKey(const Key('retry-action')), findsNothing);
      expect(repo.checkin('event-1'), isNotNull);
      await tester.pumpWidget(const SizedBox());
      repo.dispose();
    },
  );
  testWidgets(
    'onboarding step 6 saves phone/emergency contact via saveContact, normalised to E.164',
    (tester) async {
      final repo = FakeParticipantRepository();
      await show(tester, repo, 'profile6');
      await tester.enterText(find.byKey(const Key('mobile')), '0400 111 222');
      await tester.enterText(find.byKey(const Key('emergencyName')), 'Sam');
      await tester.enterText(
        find.byKey(const Key('emergencyMobile')),
        '0400 333 444',
      );
      await tester.ensureVisible(find.byKey(const Key('profile-next')));
      await tester.pumpAndSettle();
      await tester.tap(find.byKey(const Key('profile-next')));
      await tester.pumpAndSettle();
      expect(repo.calls.contains('saveContact'), true);
      expect(repo.contact['mobile'], '+61400111222');
      expect(repo.contact['emergencyContact'], {
        'name': 'Sam',
        'mobile': '+61400333444',
      });
      // Advances past the last step (7) to home, not a non-existent profile8.
      expect(find.text('Step 7 of 7'), findsOneWidget);
      await tester.pumpWidget(const SizedBox.shrink());
      repo.dispose();
    },
  );
  testWidgets(
    'onboarding step 7 (photo) can be skipped entirely; skipping never calls savePhoto',
    (tester) async {
      final repo = FakeParticipantRepository();
      await show(tester, repo, 'profile7');
      expect(find.text('Add a photo\n(optional)'), findsOneWidget);
      await tester.tap(find.byKey(const Key('profile-next')));
      await tester.pumpAndSettle();
      expect(repo.calls.contains('savePhoto'), false);
      // First-time onboarding lands on the calm "You're in" confirmation
      // (step 4 of 4) before Play, not straight on the home screen.
      expect(find.text("You're in"), findsWidgets);
      await tester.tap(find.byKey(const Key('continue-to-play')));
      await tester.pumpAndSettle();
      expect(find.text('Play near you'), findsOneWidget);
      await tester.pumpWidget(const SizedBox.shrink());
      repo.dispose();
    },
  );
  testWidgets('loading and empty states have useful copy', (tester) async {
    final repo = FakeParticipantRepository();
    repo.ready = false;
    await show(tester, repo, 'home');
    expect(find.text('Finding your next rally…'), findsOneWidget);
    await tester.pumpWidget(const SizedBox());
    repo.ready = true;
    repo.events = [];
    await show(tester, repo, 'home');
    expect(
      find.text(
        'No upcoming sessions yet. Explore programs or check back soon.',
      ),
      findsOneWidget,
    );
    await tester.pumpWidget(const SizedBox());
    repo.dispose();
  });
  testWidgets('feedback requires a rating and submits event feedback', (
    tester,
  ) async {
    final repo = FakeParticipantRepository();
    await show(tester, repo, 'feedback', event: 'event-3');
    expect(
      tester
          .widget<FilledButton>(find.byKey(const Key('send-feedback')))
          .onPressed,
      isNull,
    );
    await tester.tap(find.byKey(const Key('rating-5')));
    await tester.pump();
    await tester.ensureVisible(find.byKey(const Key('send-feedback')));
    await tester.tap(find.byKey(const Key('send-feedback')));
    await tester.pumpAndSettle();
    expect(repo.calls.contains('feedback:5'), true);
    await tester.pumpWidget(const SizedBox());
    repo.dispose();
  });
  testWidgets(
    'Me tab: tapping the avatar offers Remove photo only when a photo exists, and removing it calls savePhoto(null)',
    (tester) async {
      final repo = FakeParticipantRepository();
      await show(tester, repo, 'profile');
      await tester.tap(find.byType(CircleAvatar).first);
      await tester.pumpAndSettle();
      expect(find.text('Take a photo'), findsOneWidget);
      expect(find.text('Choose from library'), findsOneWidget);
      expect(find.text('Remove photo'), findsNothing);
      await tester.tapAt(const Offset(10, 10));
      await tester.pumpAndSettle();

      repo.profile['photoUpdatedAt'] = DateTime(2026, 11, 19);
      repo.notifyListeners();
      await tester.pumpAndSettle();
      await tester.tap(find.byType(CircleAvatar).first);
      await tester.pumpAndSettle();
      expect(find.text('Remove photo'), findsOneWidget);
      await tester.tap(find.text('Remove photo'));
      await tester.pumpAndSettle();
      expect(repo.photoRemoved, true);
      expect(repo.calls.contains('savePhoto'), true);
      await tester.pumpWidget(const SizedBox());
      repo.dispose();
    },
  );
  group('Play/Map location', () {
    testWidgets(
      'GPS granted: shows the reverse-geocoded suburb, no fallback buttons',
      (tester) async {
        final repo = FakeParticipantRepository()
          ..simulatedLocationResult = 'granted'
          ..simulatedNearbyLabel = 'Epping';
        await show(tester, repo, 'home');
        expect(repo.calls.contains('requestBrowseLocation'), true);
        expect(find.text('Near Epping'), findsOneWidget);
        expect(find.text('Use my location'), findsNothing);
        expect(find.text('Open settings'), findsNothing);
        await tester.pumpWidget(const SizedBox());
        repo.dispose();
      },
    );
    testWidgets(
      'services off: falls back to the home postcode with the fallback label and a retry button',
      (tester) async {
        final repo = FakeParticipantRepository()
          ..simulatedLocationResult = 'servicesOff';
        repo.profile['postcode'] = '2121';
        await show(tester, repo, 'home');
        expect(find.text('Near 2121 (your home postcode)'), findsOneWidget);
        expect(find.text('Use my location'), findsOneWidget);
        await tester.pumpWidget(const SizedBox());
        repo.dispose();
      },
    );
    testWidgets('permanently denied: offers Open settings instead of a retry', (
      tester,
    ) async {
      final repo = FakeParticipantRepository()
        ..simulatedLocationResult = 'deniedForever';
      repo.profile['postcode'] = '2000';
      await show(tester, repo, 'home');
      expect(find.text('Open settings'), findsOneWidget);
      await tester.pumpWidget(const SizedBox());
      repo.dispose();
    });
    testWidgets(
      'no home postcode set: falls back to a plain "Near you", not a blank postcode',
      (tester) async {
        final repo = FakeParticipantRepository()
          ..simulatedLocationResult = 'denied';
        repo.profile['postcode'] = '';
        await show(tester, repo, 'home');
        expect(find.text('Near you'), findsOneWidget);
        await tester.pumpWidget(const SizedBox());
        repo.dispose();
      },
    );
    testWidgets(
      'manual override via Change, then Use my location returns to GPS',
      (tester) async {
        final repo = FakeParticipantRepository()
          ..catalogueReady = true
          ..programs = [
            {
              'id': 'p1',
              'status': 'active',
              'name': 'Chatswood tennis',
              'sport': 'tennis',
              'venue': {
                'name': 'Chatswood Courts',
                'suburb': 'Chatswood',
                'postcode': '2067',
                'state': 'NSW',
                'lat': -33.7967,
                'lng': 151.1807,
              },
            },
          ]
          ..simulatedLocationResult = 'granted'
          ..simulatedNearbyLabel = 'Bondi Junction';
        await show(tester, repo, 'home');
        expect(find.text('Near Bondi Junction'), findsOneWidget);
        await tester.tap(find.text('Change'));
        await tester.pumpAndSettle();
        await tester.tap(find.text('Chatswood 2067'));
        await tester.pumpAndSettle();
        expect(find.text('Near Chatswood 2067'), findsOneWidget);
        expect(find.text('Use my location'), findsOneWidget);
        await tester.tap(find.text('Use my location'));
        await tester.pumpAndSettle();
        expect(find.text('Near Bondi Junction'), findsOneWidget);
        await tester.pumpWidget(const SizedBox());
        repo.dispose();
      },
    );
  });
  group('UserAvatar', () {
    testWidgets(
      'photo present: attempts to render the resolved photo, not the initial alone',
      (tester) async {
        final repo = FakeParticipantRepository()
          ..profile['photoUpdatedAt'] = DateTime(2026, 11, 19)
          ..simulatedPhotoUrl = 'https://example.test/avatar.jpg';
        await show(tester, repo, 'home');
        expect(find.byType(CachedNetworkImage), findsOneWidget);
        expect(
          tester
              .widget<CachedNetworkImage>(find.byType(CachedNetworkImage))
              .imageUrl,
          'https://example.test/avatar.jpg',
        );
        await tester.pumpWidget(const SizedBox());
        repo.dispose();
      },
    );
    testWidgets('photo missing: shows the initial, no image widget at all', (
      tester,
    ) async {
      final repo = FakeParticipantRepository();
      await show(tester, repo, 'home');
      expect(find.byType(CachedNetworkImage), findsNothing);
      expect(find.text('P'), findsOneWidget);
      await tester.pumpWidget(const SizedBox());
      repo.dispose();
    });
    testWidgets(
      'photo load error: resolving the download URL throws, falls back to the initial',
      (tester) async {
        final repo = FakeParticipantRepository()
          ..profile['photoUpdatedAt'] = DateTime(2026, 11, 19)
          ..simulatedPhotoUrlError = Exception('storage unavailable');
        await show(tester, repo, 'home');
        expect(find.byType(CachedNetworkImage), findsNothing);
        expect(find.text('P'), findsOneWidget);
        await tester.pumpWidget(const SizedBox());
        repo.dispose();
      },
    );
    testWidgets(
      'photo changed live: a profile update alone (no rebuild/restart) swaps initial for photo',
      (tester) async {
        final repo = FakeParticipantRepository();
        await show(tester, repo, 'home');
        expect(find.byType(CachedNetworkImage), findsNothing);
        expect(find.text('P'), findsOneWidget);

        repo.profile['photoUpdatedAt'] = DateTime(2026, 11, 19);
        repo.simulatedPhotoUrl = 'https://example.test/new-avatar.jpg';
        repo.notifyListeners();
        await tester.pumpAndSettle();

        expect(find.byType(CachedNetworkImage), findsOneWidget);
        expect(
          tester
              .widget<CachedNetworkImage>(find.byType(CachedNetworkImage))
              .imageUrl,
          'https://example.test/new-avatar.jpg',
        );
        await tester.pumpWidget(const SizedBox());
        repo.dispose();
      },
    );
  });
}
