import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_map/flutter_map.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:rally4ever/participant/app.dart';
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

  Future<void> showHome(WidgetTester tester, Size size) async {
    tester.view.physicalSize = size;
    tester.view.devicePixelRatio = 1;
    addTearDown(tester.view.resetPhysicalSize);
    addTearDown(tester.view.resetDevicePixelRatio);
    final repo = FakeParticipantRepository();
    await tester.pumpWidget(
      ParticipantApp(
        repository: repo,
        initialPage: 'home',
        cameraEnabled: false,
        mapTilesEnabled: false,
      ),
    );
    await tester.pumpAndSettle();
  }

  testWidgets('phone width: bottom NavigationBar, full-width content', (
    tester,
  ) async {
    await showHome(tester, const Size(390, 844));
    expect(find.byType(NavigationBar), findsOneWidget);
    expect(find.byType(NavigationRail), findsNothing);
    final listViewWidth = tester.getSize(find.byType(ListView).first).width;
    // Phone content fills the available width; well above the 720 tablet cap.
    expect(listViewWidth, greaterThan(360));
  });

  testWidgets(
    'tablet portrait (>=840 wide): side NavigationRail, content capped at 720',
    (tester) async {
      await showHome(tester, const Size(1024, 1366));
      expect(find.byType(NavigationRail), findsOneWidget);
      expect(find.byType(NavigationBar), findsNothing);
      final listViewWidth = tester.getSize(find.byType(ListView).first).width;
      expect(listViewWidth, lessThanOrEqualTo(720));
    },
  );

  testWidgets(
    'tablet landscape (>=840 wide): side NavigationRail, content capped at 720',
    (tester) async {
      await showHome(tester, const Size(1366, 1024));
      expect(find.byType(NavigationRail), findsOneWidget);
      expect(find.byType(NavigationBar), findsNothing);
      final listViewWidth = tester.getSize(find.byType(ListView).first).width;
      expect(listViewWidth, lessThanOrEqualTo(720));
    },
  );

  testWidgets(
    'just under the tablet breakpoint still uses the phone bottom bar',
    (tester) async {
      await showHome(tester, const Size(839, 1200));
      expect(find.byType(NavigationBar), findsOneWidget);
      expect(find.byType(NavigationRail), findsNothing);
    },
  );

  testWidgets(
    'map screen on a wide tablet: side rail, but the map itself stays full-bleed',
    (tester) async {
      tester.view.physicalSize = const Size(1024, 1366);
      tester.view.devicePixelRatio = 1;
      addTearDown(tester.view.resetPhysicalSize);
      addTearDown(tester.view.resetDevicePixelRatio);
      final repo = FakeParticipantRepository();
      await tester.pumpWidget(
        ParticipantApp(
          repository: repo,
          initialPage: 'map',
          cameraEnabled: false,
          mapTilesEnabled: false,
        ),
      );
      await tester.pumpAndSettle();
      expect(find.byType(NavigationRail), findsOneWidget);
      expect(find.byType(NavigationBar), findsNothing);
      // The map's own Stack isn't wrapped in the 720-cap ConstrainedBox that
      // text-content screens use -- it fills whatever the Row's Expanded
      // gives it (screen width minus the rail).
      expect(
        find.ancestor(
          of: find.byType(FlutterMap),
          matching: find.byWidgetPredicate(
            (w) => w is ConstrainedBox && w.constraints.maxWidth == 720,
          ),
        ),
        findsNothing,
      );
    },
  );
  for (final size in [
    const Size(393, 852),
    const Size(800, 1280),
    const Size(1280, 800),
  ]) {
    for (final page in [
      'welcome1',
      'welcome2',
      'welcome3',
      'account',
      'home',
      'profile',
      'help',
    ]) {
      testWidgets('$page fills the screen at ${size.width}x${size.height}', (
        tester,
      ) async {
        tester.view.physicalSize = size;
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
        final scaffold = find.byType(Scaffold).last;
        expect(tester.getSize(scaffold).width, size.width);
        expect(tester.takeException(), isNull);
        if (page == 'welcome1' || page == 'account') {
          await expectLater(
            find.byType(ParticipantApp),
            matchesGoldenFile(
              '../docs/screenshots/android20/${page}_${size.width.toInt()}x${size.height.toInt()}.png',
            ),
          );
        }

        if (page.startsWith('welcome')) {
          final box = tester.widget<Scaffold>(scaffold);
          expect(box.backgroundColor, isNot(Colors.white));
          expect(
            tester.getSize(find.byType(FilledButton).last).width,
            lessThanOrEqualTo(520),
          );
        }
      });
    }
  }
}
