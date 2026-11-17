import 'package:flutter/widgets.dart';
import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:rally4ever/participant/app.dart';

import 'support/fake_participant.dart';

void main() {
  setUpAll(() async {
    for (final name in ['Inter', 'Figtree']) {
      await (FontLoader(
        name,
      )..addFont(rootBundle.load('assets/fonts/$name.ttf'))).load();
    }
  });
  testWidgets(
    'LAN warning persists through intro and sign-in on a small phone',
    (tester) async {
      tester.view.physicalSize = const Size(320, 640);
      tester.view.devicePixelRatio = 1;
      addTearDown(tester.view.resetPhysicalSize);
      addTearDown(tester.view.resetDevicePixelRatio);
      final repo = FakeParticipantRepository(authenticated: false);
      await tester.pumpWidget(
        ParticipantApp(
          repository: repo,
          lanTesting: true,
          lanHost: '192.168.1.50',
          cameraEnabled: false,
        ),
      );
      await tester.pumpAndSettle();
      expect(find.byKey(const Key('lan-testing-banner')), findsOneWidget);
      expect(
        find.textContaining('LAN TESTING — DEVELOPMENT ONLY'),
        findsOneWidget,
      );
      expect(find.textContaining('192.168.1.50'), findsOneWidget);
      expect(tester.takeException(), isNull);
      await tester.tap(find.text('Skip'));
      await tester.pumpAndSettle();
      expect(find.byKey(const Key('lan-testing-banner')), findsOneWidget);
      expect(find.byKey(const Key('google-sign-in')), findsOneWidget);
      expect(tester.takeException(), isNull);
      await tester.pumpWidget(const SizedBox());
      repo.dispose();
    },
  );
  testWidgets('normal mode has no LAN banner', (tester) async {
    final repo = FakeParticipantRepository(authenticated: false);
    await tester.pumpWidget(
      ParticipantApp(
        repository: repo,
        initialPage: 'account',
        cameraEnabled: false,
      ),
    );
    await tester.pumpAndSettle();
    expect(find.byKey(const Key('lan-testing-banner')), findsNothing);
    await tester.pumpWidget(const SizedBox());
    repo.dispose();
  });
}
