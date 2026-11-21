import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:google_sign_in/google_sign_in.dart';
import 'package:rally4ever/participant/app.dart';
import 'package:rally4ever/participant/repository.dart';

import 'support/fake_participant.dart';

class CanceledGoogleSignInRepo extends FakeParticipantRepository {
  CanceledGoogleSignInRepo() : super(authenticated: false);
  @override
  Future<void> signInGoogle() => throw const GoogleSignInException(
    code: GoogleSignInExceptionCode.canceled,
    description: 'Cancelled by user',
    details: 16,
  );
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

  test(
    'friendlyError never leaks a GoogleSignInException, including a misleading "canceled" one',
    () {
      final message = friendlyError(
        const GoogleSignInException(
          code: GoogleSignInExceptionCode.canceled,
          description: 'Cancelled by user',
          details: 16,
        ),
      );
      expect(message, googleSignInFailedMessage);
      expect(message, isNot(contains('GoogleSignInException')));
      expect(message, isNot(contains('canceled')));
      expect(message, isNot(contains('16')));
    },
  );

  test('friendlyError maps every GoogleSignInException code the same way', () {
    for (final code in GoogleSignInExceptionCode.values) {
      expect(
        friendlyError(GoogleSignInException(code: code)),
        googleSignInFailedMessage,
      );
    }
  });

  testWidgets(
    'a canceled Google sign-in shows the calm message with Try again and Use email instead, never the raw exception',
    (tester) async {
      final repo = CanceledGoogleSignInRepo();
      await tester.pumpWidget(
        ParticipantApp(
          repository: repo,
          initialPage: 'entry',
          cameraEnabled: false,
        ),
      );
      await tester.pumpAndSettle();
      await tester.tap(find.byKey(const Key('google-sign-in')));
      await tester.pumpAndSettle();

      expect(find.text(googleSignInFailedMessage), findsOneWidget);
      expect(find.textContaining('GoogleSignInException'), findsNothing);
      expect(find.textContaining('canceled'), findsNothing);
      expect(find.textContaining('Cancelled by user'), findsNothing);
      expect(find.byKey(const Key('google-signin-retry')), findsOneWidget);
      expect(find.byKey(const Key('google-signin-use-email')), findsOneWidget);
      expect(find.text('Try again'), findsOneWidget);
      expect(find.text('Use email instead'), findsOneWidget);
      // Never the app's red-error styling -- the calm pink/navy banner.
      final text = tester.widget<Text>(find.text(googleSignInFailedMessage));
      expect(text.style?.color, isNot(Colors.red));

      await tester.tap(find.byKey(const Key('google-signin-use-email')));
      await tester.pumpAndSettle();
      // FakeParticipantRepository defaults hasSignedInBefore to true, so
      // "Use email instead" lands on Sign in, not Create account.
      expect(find.byKey(const Key('authenticate')), findsOneWidget);
      expect(find.text('Welcome\nback'), findsOneWidget);
    },
  );
}
