import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:integration_test/integration_test.dart';
import 'package:rally4ever/participant/app.dart';
import 'package:timezone/data/latest.dart' as tz;

import '../test/support/fake_participant.dart';

void main() {
  final binding = IntegrationTestWidgetsFlutterBinding.ensureInitialized();
  testWidgets('capture About you pass 2 on the Android emulator flavour', (
    tester,
  ) async {
    tz.initializeTimeZones();
    var converted = false;
    for (final step in [1, 2, 4, 5, 6]) {
      final repo = FakeParticipantRepository();
      await tester.pumpWidget(
        ParticipantApp(
          key: ValueKey(step),
          repository: repo,
          initialPage: 'profile$step',
          cameraEnabled: false,
          mapTilesEnabled: false,
        ),
      );
      await tester.pumpAndSettle();
      if (!converted) {
        await binding.convertFlutterSurfaceToImage();
        converted = true;
        await tester.pumpAndSettle();
      }
      expect(tester.takeException(), isNull);
      await binding.takeScreenshot('step-$step');
      if (step == 2) {
        await tester.tap(find.text('Why we ask').first);
        await tester.pumpAndSettle();
        await binding.takeScreenshot('step-2-why');
        await tester.tap(find.text('Got it'));
        await tester.pumpAndSettle();
      }
      if (step == 6) {
        await tester.ensureVisible(find.byKey(const Key('profile-next')));
        await tester.pumpAndSettle();
        await binding.takeScreenshot('step-6-bottom');
      }
      await tester.pumpWidget(const SizedBox.shrink());
      repo.dispose();
    }
  });
}
