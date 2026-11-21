import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:rally4ever/participant/app.dart';
import 'package:rally4ever/participant/forms.dart';
import 'package:timezone/data/latest.dart' as tz;

import 'support/fake_participant.dart';

void main() {
  setUpAll(() async {
    tz.initializeTimeZones();
    await (FontLoader(
      'MaterialIcons',
    )..addFont(rootBundle.load('fonts/MaterialIcons-Regular.otf'))).load();
    await (FontLoader(
      'Inter',
    )..addFont(rootBundle.load('assets/fonts/Inter.ttf'))).load();
    await (FontLoader('Jellee')..addFont(
          rootBundle.load('assets/fonts/Jellee_1223/TTF/Jellee-Bold.ttf'),
        ))
        .load();
  });

  Future<void> show(WidgetTester tester, String page) async {
    tester.view.physicalSize = const Size(390, 1400);
    tester.view.devicePixelRatio = 1;
    addTearDown(tester.view.resetPhysicalSize);
    addTearDown(tester.view.resetDevicePixelRatio);
    await tester.pumpWidget(
      ParticipantApp(
        repository: FakeParticipantRepository(),
        initialPage: page,
        cameraEnabled: false,
        mapTilesEnabled: false,
      ),
    );
    await tester.pumpAndSettle();
  }

  testWidgets('step 1 shows the postcode privacy note', (tester) async {
    await show(tester, 'profile1');
    expect(
      find.text(
        "We use your postcode to show programs nearby. It's never shown "
        'to other members.',
      ),
      findsOneWidget,
    );
    expect(find.byIcon(Icons.info_outline), findsOneWidget);
  });

  testWidgets('step 2 shows a "Why we ask" button for each optional question', (
    tester,
  ) async {
    await show(tester, 'profile2');
    expect(find.text('Why we ask'), findsNWidgets(2));
    expect(find.byIcon(Icons.help_outline), findsNWidgets(2));
  });

  testWidgets(
    'tapping "Why we ask" opens a sheet with its title and Got it, which closes it',
    (tester) async {
      await show(tester, 'profile2');
      await tester.tap(find.text('Why we ask').first);
      await tester.pumpAndSettle();

      expect(find.text('Why we ask'), findsWidgets);
      expect(
        find.textContaining(
          "It helps us see who we're reaching and make sure sessions",
        ),
        findsOneWidget,
      );
      expect(find.text('Got it'), findsOneWidget);

      await tester.tap(find.text('Got it'));
      await tester.pumpAndSettle();
      expect(
        find.textContaining(
          "It helps us see who we're reaching and make sure sessions",
        ),
        findsNothing,
      );
      expect(find.text('Got it'), findsNothing);
    },
  );

  testWidgets(
    'step 3 "Why we ask" buttons each open their own explanation',
    (tester) async {
      await show(tester, 'profile3');
      expect(find.text('Why we ask'), findsNWidgets(3));

      await tester.tap(find.text('Why we ask').at(2));
      await tester.pumpAndSettle();
      expect(
        find.textContaining('which posters, partners and events'),
        findsOneWidget,
      );
      await tester.tap(find.text('Got it'));
      await tester.pumpAndSettle();
    },
  );

  testWidgets(
    'no overflow at 360x640 with 1.5x text scale on step 2',
    (tester) async {
      tester.view.physicalSize = const Size(360, 640);
      tester.view.devicePixelRatio = 1;
      tester.platformDispatcher.textScaleFactorTestValue = 1.5;
      addTearDown(tester.view.resetPhysicalSize);
      addTearDown(tester.view.resetDevicePixelRatio);
      addTearDown(tester.platformDispatcher.clearTextScaleFactorTestValue);
      await tester.pumpWidget(
        ParticipantApp(
          repository: FakeParticipantRepository(),
          initialPage: 'profile2',
          cameraEnabled: false,
          mapTilesEnabled: false,
        ),
      );
      await tester.pumpAndSettle();
      expect(tester.takeException(), isNull);
      expect(find.byType(WhyWeAsk), findsNWidgets(2));

      await tester.tap(find.text('Why we ask').first);
      await tester.pumpAndSettle();
      expect(tester.takeException(), isNull);
      expect(find.text('Got it'), findsOneWidget);
    },
  );
}
