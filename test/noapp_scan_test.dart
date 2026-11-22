import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:rally4ever/participant/app.dart';

import 'support/fake_participant.dart';

/// Item 6: "Check in without an app account" is camera-first. The real
/// camera plugin can't run in a widget test, so every test here drives the
/// flow through `cameraEnabled: false`, which renders the same calm
/// fallback a denied/unavailable camera shows on a real device -- the
/// "Can't scan? Enter the code instead" text entry stands in for an actual
/// scan throughout.
const _validLink =
    'https://rally4ever.org/c/EVENT-1?k=AAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAA';

void main() {
  Future<void> pumpNoApp(WidgetTester tester, {String? noAppFormsError}) async {
    tester.view.physicalSize = const Size(390, 1600);
    tester.view.devicePixelRatio = 1;
    addTearDown(tester.view.resetPhysicalSize);
    addTearDown(tester.view.resetDevicePixelRatio);
    final repo = FakeParticipantRepository(authenticated: false)
      ..noAppFormsError = noAppFormsError;
    await tester.pumpWidget(
      ParticipantApp(
        repository: repo,
        initialPage: 'noapp',
        cameraEnabled: false,
      ),
    );
    await tester.pumpAndSettle();
  }

  Future<void> enterCode(WidgetTester tester, String value) async {
    await tester.tap(find.byKey(const Key('toggle-paste-link')));
    await tester.pumpAndSettle();
    await tester.enterText(find.byKey(const Key('noapp-qr')), value);
    await tester.tap(find.byKey(const Key('noapp-use-code')));
    await tester.pumpAndSettle();
  }

  testWidgets(
    'a denied/unavailable camera shows the calm fallback, with a link to the code entry and to Settings',
    (tester) async {
      await pumpNoApp(tester);
      expect(
        find.textContaining("We can't reach the camera"),
        findsOneWidget,
      );
      expect(find.byKey(const Key('open-camera-settings')), findsOneWidget);
      expect(find.byKey(const Key('toggle-paste-link')), findsOneWidget);
      expect(
        find.text("Can't scan? Enter the code instead"),
        findsOneWidget,
      );
    },
  );

  testWidgets(
    'the fallback text entry still works: a valid code shows the confirmation card, and Continue reaches the details step',
    (tester) async {
      await pumpNoApp(tester);
      await enterCode(tester, _validLink);

      expect(find.text("You're checking in"), findsOneWidget);
      expect(find.text('Weeknight Rally'), findsOneWidget);
      expect(find.textContaining('Waverley Park'), findsOneWidget);
      expect(find.widgetWithText(FilledButton, 'Continue'), findsOneWidget);

      await tester.tap(find.byKey(const Key('confirm-session')));
      await tester.pumpAndSettle();
      // "Your details" appears twice: the StepBar's own label and the
      // page's headline -- both intentional.
      expect(find.text('Your details'), findsWidgets);
      expect(find.text('STEP 1 OF 3'), findsOneWidget);
    },
  );

  testWidgets(
    'an invalid code (bad format) shows a gentle message and stays on the scanner',
    (tester) async {
      await pumpNoApp(tester);
      await enterCode(tester, 'not a real link');
      expect(
        find.text(
          "That doesn't look like a RALLY4EVER session code. Ask your coach to show the current one.",
        ),
        findsOneWidget,
      );
      expect(find.byKey(const Key('scan-again')), findsOneWidget);
      expect(find.byKey(const Key('noapp-scanner')), findsNothing);
      expect(find.text("You're checking in"), findsNothing);
    },
  );

  testWidgets(
    'an expired/unknown code (right shape, rejected by the backend) shows a gentle message and stays on the scanner',
    (tester) async {
      await pumpNoApp(
        tester,
        noAppFormsError: 'This code expired. Scan the current coach QR.',
      );
      await enterCode(tester, _validLink);
      expect(
        find.text('This code expired. Scan the current coach QR.'),
        findsOneWidget,
      );
      expect(find.byKey(const Key('scan-again')), findsOneWidget);
      expect(find.text("You're checking in"), findsNothing);
    },
  );
}
