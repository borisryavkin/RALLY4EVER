import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:rally4ever/participant/app.dart';

import 'redesign_verify_test.dart'
    show NoAppSessionRepo, StillUnverifiedRepo, validSessionLink;
import 'support/fake_participant.dart';

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

  for (final page in ['entry', 'signin', 'signup', 'noapp']) {
    testWidgets(
      '$page renders without overflow at 1.5x text scale',
      (tester) async {
        tester.view.physicalSize = const Size(390, 844);
        tester.view.devicePixelRatio = 1;
        tester.platformDispatcher.textScaleFactorTestValue = 1.5;
        addTearDown(tester.view.resetPhysicalSize);
        addTearDown(tester.view.resetDevicePixelRatio);
        addTearDown(
          tester.platformDispatcher.clearTextScaleFactorTestValue,
        );
        final repo = FakeParticipantRepository(authenticated: false);
        await tester.pumpWidget(
          ParticipantApp(
            repository: repo,
            initialPage: page,
            cameraEnabled: false,
          ),
        );
        await tester.pumpAndSettle();
        expect(tester.takeException(), isNull);
      },
    );
  }

  testWidgets(
    'the email-verification panel renders without overflow at 1.5x text scale',
    (tester) async {
      tester.view.physicalSize = const Size(390, 844);
      tester.view.devicePixelRatio = 1;
      tester.platformDispatcher.textScaleFactorTestValue = 1.5;
      addTearDown(tester.view.resetPhysicalSize);
      addTearDown(tester.view.resetDevicePixelRatio);
      addTearDown(tester.platformDispatcher.clearTextScaleFactorTestValue);
      final repo = StillUnverifiedRepo();
      await tester.pumpWidget(
        ParticipantApp(
          repository: repo,
          initialPage: 'signup',
          cameraEnabled: false,
        ),
      );
      await tester.pumpAndSettle();
      await tester.enterText(
        find.byKey(const Key('email')),
        'new@example.test',
      );
      await tester.enterText(
        find.byKey(const Key('password')),
        'Test-password-1',
      );
      await tester.tap(find.byKey(const Key('authenticate')));
      await tester.pumpAndSettle();
      expect(tester.takeException(), isNull);
    },
  );

  testWidgets(
    'the full check-in-without-an-account flow renders without overflow at 1.5x text scale',
    (tester) async {
      // Tall enough that every step's Continue button stays reachable by a
      // plain tap even with 1.5x text inflating each step's content height.
      tester.view.physicalSize = const Size(390, 2600);
      tester.view.devicePixelRatio = 1;
      tester.platformDispatcher.textScaleFactorTestValue = 1.5;
      addTearDown(tester.view.resetPhysicalSize);
      addTearDown(tester.view.resetDevicePixelRatio);
      addTearDown(tester.platformDispatcher.clearTextScaleFactorTestValue);
      final repo = NoAppSessionRepo()..beginResult = {'status': 'confirmed'};
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
      expect(tester.takeException(), isNull);

      await tester.enterText(
        find.byKey(const Key('noapp-qr')),
        validSessionLink,
      );
      await tester.tap(find.byKey(const Key('noapp-use-code')));
      await tester.pumpAndSettle();
      expect(tester.takeException(), isNull);

      await tester.tap(find.byKey(const Key('confirm-session')));
      await tester.pumpAndSettle();
      expect(tester.takeException(), isNull);

      await tester.enterText(
        find.byKey(const Key('noapp-email')),
        'person@example.test',
      );
      await tester.enterText(find.byKey(const Key('noapp-firstName')), 'Alex');
      await tester.enterText(
        find.byKey(const Key('noapp-mobile')),
        '0400000000',
      );
      await tester.enterText(
        find.byKey(const Key('noapp-emergencyName')),
        'Sam',
      );
      await tester.enterText(
        find.byKey(const Key('noapp-emergencyMobile')),
        '0400000001',
      );
      await tester.pumpAndSettle();
      expect(tester.takeException(), isNull);

      await tester.tap(find.byKey(const Key('details-continue')));
      await tester.pumpAndSettle();
      expect(tester.takeException(), isNull);

      await tester.tap(find.byKey(const Key('agree-conduct')));
      await tester.pumpAndSettle();
      await tester.tap(find.byKey(const Key('agreement-continue')));
      await tester.pumpAndSettle();
      expect(tester.takeException(), isNull);

      await tester.tap(find.byKey(const Key('agreement-continue')));
      await tester.pumpAndSettle();
      expect(tester.takeException(), isNull);
      expect(find.text("You're checked in"), findsOneWidget);
    },
  );
}
