import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:rally4ever/participant/app.dart';
import 'package:timezone/data/latest.dart' as tz;

import 'support/fake_participant.dart';

/// "At the court" (page 'checkin') window-open/distance tests, driven by
/// the fake repository's own clock rather than the wall clock, per the
/// task's "fake clock" requirement. The window/closed booleans compare
/// absolute Timestamp instants (never wall-clock strings), so these are
/// inherently timezone- and DST-safe; the tests below confirm that
/// directly rather than just asserting it in a comment.
void main() {
  setUpAll(() async {
    tz.initializeTimeZones();
    await (FontLoader(
      'MaterialIcons',
    )..addFont(rootBundle.load('fonts/MaterialIcons-Regular.otf'))).load();
    await (FontLoader(
      'Inter',
    )..addFont(rootBundle.load('assets/fonts/Inter.ttf'))).load();
  });

  Future<void> show(WidgetTester tester, FakeParticipantRepository repo) async {
    tester.view.physicalSize = const Size(390, 1200);
    tester.view.devicePixelRatio = 1;
    addTearDown(tester.view.resetPhysicalSize);
    addTearDown(tester.view.resetDevicePixelRatio);
    await tester.pumpWidget(
      ParticipantApp(
        repository: repo,
        initialPage: 'checkin',
        initialEventId: 'event-1',
        cameraEnabled: false,
        mapTilesEnabled: false,
      ),
    );
    await tester.pumpAndSettle();
  }

  bool scanEnabled(WidgetTester tester) =>
      tester.widget<FilledButton>(find.byKey(const Key('start-scan'))).onPressed !=
      null;

  testWidgets('just before the window: scan disabled, shows "opens at"', (
    tester,
  ) async {
    final repo = FakeParticipantRepository();
    final start = repo.now().add(const Duration(minutes: 20));
    repo.events[0]['startsAt'] = start;
    repo.events[0]['endsAt'] = start.add(const Duration(hours: 1));
    // Window opens 10 minutes before start -- 10 minutes out is 1 second
    // before that, still closed.
    repo.clock = start
        .subtract(const Duration(minutes: 10))
        .subtract(const Duration(seconds: 1));
    await show(tester, repo);
    expect(scanEnabled(tester), false);
    expect(find.textContaining('Check-in opens\nat'), findsOneWidget);
  });

  testWidgets('exactly at window open: scan is enabled', (tester) async {
    final repo = FakeParticipantRepository();
    final start = repo.now().add(const Duration(minutes: 20));
    repo.events[0]['startsAt'] = start;
    repo.events[0]['endsAt'] = start.add(const Duration(hours: 1));
    repo.clock = start.subtract(const Duration(minutes: 10));
    await show(tester, repo);
    expect(scanEnabled(tester), true);
    expect(find.text('Ready to play?\nScan to check in'), findsOneWidget);
  });

  testWidgets('inside the window: scan is enabled', (tester) async {
    final repo = FakeParticipantRepository();
    // Default fixture already sets event-1 to be mid-session relative to
    // repo.now() (startsAt 5 minutes ago, endsAt in an hour).
    await show(tester, repo);
    expect(scanEnabled(tester), true);
  });

  testWidgets('after close: scan disabled, shows "closed"', (tester) async {
    final repo = FakeParticipantRepository();
    repo.events[0]['startsAt'] = repo.now().subtract(const Duration(hours: 2));
    repo.events[0]['endsAt'] = repo.now().subtract(const Duration(hours: 1));
    await show(tester, repo);
    expect(scanEnabled(tester), false);
    expect(find.text('Check-in has\nclosed'), findsOneWidget);
  });

  testWidgets(
    'a venue in a different timezone shows the correct LOCAL opening time, not device/UTC time',
    (tester) async {
      final repo = FakeParticipantRepository();
      // A fixed real-world instant: 2026-06-10 03:00 UTC is 2026-06-10
      // 11:00am in Perth (UTC+8, no DST in June) and 2026-06-10 1:00pm in
      // Sydney (UTC+10 in June, outside DST) -- deliberately different
      // from each other so a timezone mixup would show the wrong one.
      final instant = DateTime.utc(2026, 6, 10, 3, 0);
      repo.events[0]['timezone'] = 'Australia/Perth';
      repo.events[0]['startsAt'] = instant.add(const Duration(minutes: 20));
      repo.events[0]['endsAt'] = instant.add(const Duration(hours: 1, minutes: 20));
      repo.clock = instant;
      await show(tester, repo);
      // Opens 10 minutes before startsAt: 11:10am Perth time.
      expect(find.text('Check-in opens\nat 11:10am'), findsOneWidget);
    },
  );

  testWidgets(
    'the open/closed window is unaffected by a daylight-saving transition, because it compares absolute instants',
    (tester) async {
      final repo = FakeParticipantRepository();
      // Australian DST ended 2026-04-05 03:00 AEDT -> 02:00 AEST (an hour
      // "repeats" in wall-clock terms). A session starting right on that
      // boundary must still open exactly 10 minutes of real elapsed time
      // beforehand, regardless of the wall-clock discontinuity.
      final startUtc = DateTime.utc(2026, 4, 4, 16, 0); // 2026-04-05 03:00 AEDT
      repo.events[0]['timezone'] = 'Australia/Sydney';
      repo.events[0]['startsAt'] = startUtc;
      repo.events[0]['endsAt'] = startUtc.add(const Duration(hours: 1));
      repo.clock = startUtc.subtract(const Duration(minutes: 10, seconds: 1));
      await show(tester, repo);
      expect(scanEnabled(tester), false);
      await tester.pumpWidget(const SizedBox());
      repo.dispose();

      final repo2 = FakeParticipantRepository();
      repo2.events[0]['timezone'] = 'Australia/Sydney';
      repo2.events[0]['startsAt'] = startUtc;
      repo2.events[0]['endsAt'] = startUtc.add(const Duration(hours: 1));
      repo2.clock = startUtc.subtract(const Duration(minutes: 10));
      await show(tester, repo2);
      expect(scanEnabled(tester), true);
    },
  );

  testWidgets(
    'distance 0 m, 149 m and 151 m (geofence 150 m) are all shown but never disable the scan button',
    (tester) async {
      for (final distance in [0.0, 149.0, 151.0]) {
        final repo = FakeParticipantRepository();
        // geofenceRadiusM is 150 by default on the event-1 fixture; place
        // the simulated device roughly `distance` metres north of the
        // venue (small enough offsets that metres-per-degree is ~stable).
        final venue = repo.events[0]['venue'] as Map;
        repo.simulatedLocation = {
          'lat': (venue['lat'] as num) + distance / 111320,
          'lng': venue['lng'],
        };
        await show(tester, repo);
        await tester.ensureVisible(find.byKey(const Key('preview-distance')));
        await tester.tap(find.byKey(const Key('preview-distance')));
        await tester.pumpAndSettle();
        final shown = tester
            .widgetList<Text>(find.textContaining('m from the venue'))
            .single
            .data!;
        final shownMetres = int.parse(RegExp(r'(\d+) m from').firstMatch(shown)!.group(1)!);
        expect(
          (shownMetres - distance).abs() <= 2,
          true,
          reason: 'distance $distance, shown "$shown"',
        );
        expect(scanEnabled(tester), true, reason: 'distance $distance');
        await tester.pumpWidget(const SizedBox());
        repo.dispose();
      }
    },
  );

  testWidgets(
    'unknown location (permission denied / GPS off) shows a calm message, never blocks scanning',
    (tester) async {
      final repo = FakeParticipantRepository();
      repo.locationError = 'Allow location access to check your distance from the court.';
      await show(tester, repo);
      await tester.ensureVisible(find.byKey(const Key('preview-distance')));
      await tester.tap(find.byKey(const Key('preview-distance')));
      await tester.pumpAndSettle();
      expect(find.textContaining("We couldn't find your location"), findsOneWidget);
      expect(find.textContaining('Exception'), findsNothing);
      expect(find.textContaining('StateError'), findsNothing);
      expect(scanEnabled(tester), true);
    },
  );

  testWidgets(
    'a venue with no coordinates on file never shows a distance check or crashes, and scanning still works',
    (tester) async {
      final repo = FakeParticipantRepository();
      (repo.events[0]['venue'] as Map)
        ..remove('lat')
        ..remove('lng');
      await show(tester, repo);
      expect(tester.takeException(), isNull);
      expect(find.byKey(const Key('preview-distance')), findsNothing);
      expect(find.textContaining("don’t have an exact location"), findsOneWidget);
      expect(scanEnabled(tester), true);
    },
  );

  testWidgets(
    'a venue at exactly 0,0 ("null island") is treated the same as missing, not a real location',
    (tester) async {
      final repo = FakeParticipantRepository();
      (repo.events[0]['venue'] as Map)
        ..['lat'] = 0
        ..['lng'] = 0;
      await show(tester, repo);
      expect(find.byKey(const Key('preview-distance')), findsNothing);
      expect(scanEnabled(tester), true);
    },
  );

  testWidgets('the large QR circle is itself a tappable scan button when the window is open', (
    tester,
  ) async {
    final repo = FakeParticipantRepository();
    await show(tester, repo);
    expect(scanEnabled(tester), true);
    await tester.tap(find.byKey(const Key('scan-circle')));
    await tester.pumpAndSettle();
    expect(find.byKey(const Key('qr-link')), findsOneWidget); // landed on 'scan'
  });

  testWidgets('the QR circle is not tappable when the window is closed', (tester) async {
    final repo = FakeParticipantRepository();
    repo.events[0]['startsAt'] = repo.now().add(const Duration(hours: 1));
    await show(tester, repo);
    expect(scanEnabled(tester), false);
    await tester.tap(find.byKey(const Key('scan-circle')));
    await tester.pumpAndSettle();
    expect(find.byKey(const Key('qr-link')), findsNothing); // did not navigate
  });
}
