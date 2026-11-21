import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
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

class StillUnverifiedRepo extends FakeParticipantRepository {
  StillUnverifiedRepo() : super(authenticated: false);
  @override
  Future<void> refreshVerification() async {}
}

/// A valid signed session link, matching CheckInLink.parse's format: an
/// https://rally4ever.org/c/`eventCode`?k=`43-char secret` URL.
const validSessionLink =
    'https://rally4ever.org/c/EVENT-1?k=odJFCrnl2edlBDdz1C5Jau2RJtBRnlWmTSHf6pWkLUy';

/// Stands in for getNoAppForms/beginNoAppCheckIn so the confirmation card,
/// details step and agreements step can be driven without touching a real
/// backend.
class NoAppSessionRepo extends FakeParticipantRepository {
  NoAppSessionRepo() : super(authenticated: false);
  List<Record> agreementForms = [
    {
      'id': 'conduct',
      'title': 'Code of conduct',
      'required': true,
      'version': 1,
      'content': 'Be kind and inclusive.',
    },
    {
      'id': 'waiver',
      'title': 'Liability waiver',
      'required': false,
      'version': 1,
      'content': 'Play at a pace that feels right for you.',
    },
  ];
  Record? beginResult;
  @override
  Future<Record> call(String name, Record data) async {
    calls.add(name);
    if (name == 'getNoAppForms') {
      return {
        'eventId': 'event-1',
        'name': 'Bondi Junction tennis',
        'venue': {'name': 'Community courts', 'suburb': 'Bondi Junction'},
        'startsAt': DateTime.utc(2026, 11, 20, 7, 30).toIso8601String(),
        'endsAt': DateTime.utc(2026, 11, 20, 8, 30).toIso8601String(),
        'timezone': 'Australia/Sydney',
        'forms': agreementForms,
      };
    }
    if (name == 'beginNoAppCheckIn') {
      return beginResult ?? {'status': 'pending'};
    }
    return super.call(name, data);
  }
}

void main() {
  setUpAll(() async {
    for (final name in ['Inter']) {
      await (FontLoader(
        name,
      )..addFont(rootBundle.load('assets/fonts/$name.ttf'))).load();
    }
    await (FontLoader('Jellee')..addFont(
          rootBundle.load('assets/fonts/Jellee_1223/TTF/Jellee-Bold.ttf'),
        ))
        .load();
  });

  group('sign-up: keyboard dismiss and scroll after submission', () {
    testWidgets(
      'submitting the sign-up form unfocuses the keyboard and scrolls the verification panel into view',
      (tester) async {
        setTallView(tester);
        final repo = StillUnverifiedRepo();
        await tester.pumpWidget(
          ParticipantApp(
            repository: repo,
            initialPage: 'signup',
            cameraEnabled: false,
          ),
        );
        await tester.pumpAndSettle();
        await tester.tap(find.byKey(const Key('password')));
        await tester.enterText(
          find.byKey(const Key('email')),
          'new@example.test',
        );
        await tester.enterText(
          find.byKey(const Key('password')),
          'Test-password-1',
        );
        expect(tester.testTextInput.isVisible, isTrue);

        await tester.tap(find.byKey(const Key('authenticate')));
        await tester.pumpAndSettle();

        expect(tester.testTextInput.isVisible, isFalse);
        expect(find.textContaining('new@example.test'), findsOneWidget);
        expect(
          tester.getRect(find.byKey(const Key('open-email-app'))).top,
          greaterThanOrEqualTo(0),
        );
      },
    );
  });

  group('check-in: camera-permission fallback', () {
    testWidgets(
      'no camera available shows a friendly explanation with a settings button, never a raw permission error',
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
        expect(
          find.text(
            "We can't reach the camera. Enter a code or link instead, or allow camera access in Settings.",
          ),
          findsOneWidget,
        );
        expect(find.byKey(const Key('open-camera-settings')), findsOneWidget);
        expect(find.textContaining('Permission'), findsNothing);
        expect(find.textContaining('Exception'), findsNothing);
      },
    );
  });

  group('check-in: confirmation card', () {
    testWidgets(
      'a valid session code shows "Is this your session?" with session details, Yes/Scan again',
      (tester) async {
        setTallView(tester);
        final repo = NoAppSessionRepo();
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
          validSessionLink,
        );
        await tester.tap(find.byKey(const Key('noapp-use-code')));
        await tester.pumpAndSettle();

        expect(find.text('Is this your session?'), findsOneWidget);
        expect(find.text('Bondi Junction tennis'), findsOneWidget);
        expect(
          find.textContaining('Community courts, Bondi Junction'),
          findsOneWidget,
        );
        expect(find.byKey(const Key('confirm-session')), findsOneWidget);
        expect(find.byKey(const Key('scan-again')), findsOneWidget);

        await tester.tap(find.byKey(const Key('scan-again')));
        await tester.pumpAndSettle();
        expect(find.text('Is this your session?'), findsNothing);
        expect(find.byKey(const Key('toggle-paste-link')), findsOneWidget);
      },
    );
  });

  group('check-in: your details', () {
    testWidgets(
      'Check in stays disabled and shows what is missing until required fields are filled',
      (tester) async {
        setTallView(tester);
        final repo = NoAppSessionRepo();
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
          validSessionLink,
        );
        await tester.tap(find.byKey(const Key('noapp-use-code')));
        await tester.pumpAndSettle();
        await tester.tap(find.byKey(const Key('confirm-session')));
        await tester.pumpAndSettle();

        // Appears twice: the StepBar's own step-2 label, and the screen's
        // big headline reinforcing it -- both intentional, not a bug.
        expect(find.text('Your details'), findsNWidgets(2));
        expect(find.textContaining('So we can reach someone'), findsOneWidget);
        var continueButton = tester.widget<FilledButton>(
          find.byKey(const Key('details-continue')),
        );
        expect(continueButton.onPressed, isNull);
        expect(find.byKey(const Key('missing-details')), findsOneWidget);
        expect(
          find.textContaining('Still needed:'),
          findsOneWidget,
        );

        await tester.enterText(
          find.byKey(const Key('noapp-email')),
          'person@example.test',
        );
        await tester.enterText(
          find.byKey(const Key('noapp-firstName')),
          'Alex',
        );
        await tester.enterText(find.byKey(const Key('noapp-mobile')), '0400000000');
        await tester.enterText(
          find.byKey(const Key('noapp-emergencyName')),
          'Sam',
        );
        await tester.enterText(
          find.byKey(const Key('noapp-emergencyMobile')),
          '0400000001',
        );
        await tester.pumpAndSettle();

        expect(find.byKey(const Key('missing-details')), findsNothing);
        continueButton = tester.widget<FilledButton>(
          find.byKey(const Key('details-continue')),
        );
        expect(continueButton.onPressed, isNotNull);
      },
    );
  });

  group('check-in: agreements shown one at a time', () {
    Future<void> reachAgreements(WidgetTester tester, NoAppSessionRepo repo) async {
      setTallView(tester);
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
        validSessionLink,
      );
      await tester.tap(find.byKey(const Key('noapp-use-code')));
      await tester.pumpAndSettle();
      await tester.tap(find.byKey(const Key('confirm-session')));
      await tester.pumpAndSettle();
      await tester.enterText(
        find.byKey(const Key('noapp-email')),
        'person@example.test',
      );
      await tester.enterText(find.byKey(const Key('noapp-firstName')), 'Alex');
      await tester.enterText(find.byKey(const Key('noapp-mobile')), '0400000000');
      await tester.enterText(
        find.byKey(const Key('noapp-emergencyName')),
        'Sam',
      );
      await tester.enterText(
        find.byKey(const Key('noapp-emergencyMobile')),
        '0400000001',
      );
      await tester.pumpAndSettle();
      await tester.tap(find.byKey(const Key('details-continue')));
      await tester.pumpAndSettle();
    }

    testWidgets(
      'required forms block Check in until agreed, shown one at a time, finishing with You\'re checked in',
      (tester) async {
        final repo = NoAppSessionRepo()..beginResult = {'status': 'confirmed'};
        await reachAgreements(tester, repo);

        expect(find.text('Agreement 1 of 2'), findsOneWidget);
        expect(find.text('Code of conduct'), findsOneWidget);
        var agreeContinue = tester.widget<FilledButton>(
          find.byKey(const Key('agreement-continue')),
        );
        expect(agreeContinue.onPressed, isNull);

        await tester.tap(find.byKey(const Key('agree-conduct')));
        await tester.pumpAndSettle();
        agreeContinue = tester.widget<FilledButton>(
          find.byKey(const Key('agreement-continue')),
        );
        expect(agreeContinue.onPressed, isNotNull);
        await tester.tap(find.byKey(const Key('agreement-continue')));
        await tester.pumpAndSettle();

        expect(find.text('Agreement 2 of 2'), findsOneWidget);
        expect(find.text('Liability waiver'), findsOneWidget);
        // Not required -- Check in is already enabled without ticking it.
        agreeContinue = tester.widget<FilledButton>(
          find.byKey(const Key('agreement-continue')),
        );
        expect(agreeContinue.onPressed, isNotNull);
        expect(find.text('Check in'), findsOneWidget);

        await tester.tap(find.byKey(const Key('agreement-continue')));
        await tester.pumpAndSettle();

        expect(find.text("You're checked in"), findsOneWidget);
      },
    );

    testWidgets(
      'a session with no forms blocks with a friendly message instead of a dead end',
      (tester) async {
        final repo = NoAppSessionRepo()..agreementForms = [];
        await reachAgreements(tester, repo);

        expect(
          find.text(
            "This session needs a form that isn't available yet. Please see your coach.",
          ),
          findsOneWidget,
        );
        expect(find.text('Back'), findsOneWidget);
      },
    );
  });
}
