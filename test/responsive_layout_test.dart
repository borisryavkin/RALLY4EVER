import 'package:flutter/material.dart';
import 'package:flutter_map/flutter_map.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:rally4ever/participant/app.dart';
import 'package:timezone/data/latest.dart' as tz;

import 'support/fake_participant.dart';

void main() {
  setUpAll(() {
    tz.initializeTimeZones();
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
}
