import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:rally4ever/participant/app.dart';

import 'support/fake_participant.dart';

class RejectedSignIn extends FakeParticipantRepository {
  @override
  Future<void> signIn(String email, String password) async {
    await Future<void>.delayed(const Duration(milliseconds: 20));
    throw StateError('Email or app password did not match.');
  }
}

void main() {
  testWidgets(
    'busy and error banners preserve login fields and expose recovery',
    (tester) async {
      tester.view.physicalSize = const Size(390, 1100);
      tester.view.devicePixelRatio = 1;
      addTearDown(tester.view.resetPhysicalSize);
      addTearDown(tester.view.resetDevicePixelRatio);
      final repo = RejectedSignIn()
        ..uid = null
        ..verified = false
        ..email = null;
      await tester.pumpWidget(
        ParticipantApp(
          repository: repo,
          initialPage: 'account',
          cameraEnabled: false,
          mapTilesEnabled: false,
        ),
      );
      await tester.pumpAndSettle();
      await tester.enterText(
        find.byKey(const Key('email')),
        'person@example.test',
      );
      await tester.enterText(find.byKey(const Key('password')), 'app-password');
      await tester.ensureVisible(find.byKey(const Key('authenticate')));
      await tester.tap(find.byKey(const Key('authenticate')));
      await tester.pump();
      await tester.pumpAndSettle();
      expect(
        tester
            .widget<TextField>(find.byKey(const Key('email')))
            .controller!
            .text,
        'person@example.test',
      );
      expect(
        tester
            .widget<TextField>(find.byKey(const Key('password')))
            .controller!
            .text,
        'app-password',
      );
      expect(find.text('Set or reset app password'), findsOneWidget);
      await tester.ensureVisible(find.byKey(const Key('show-login-password')));
      await tester.tap(find.byKey(const Key('show-login-password')));
      await tester.pump();
      expect(
        tester.widget<TextField>(find.byKey(const Key('password'))).obscureText,
        false,
      );
    },
  );
}
