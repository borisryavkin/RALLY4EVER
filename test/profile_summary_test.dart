import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:rally4ever/participant/app.dart';
import 'package:rally4ever/participant/profile_summary.dart';

import 'support/fake_participant.dart';

void main() {
  test('history deduplicates attendance, excludes cancelled intent, and never counts future RSVP as missed', () {
    final repo = FakeParticipantRepository();
    repo.events = [
      for (final id in ['past', 'future', 'attended', 'cancelled'])
        {
          'id': id,
          'startsAt': repo.now().add(Duration(days: id == 'future' ? 1 : -1)),
          'endsAt': repo.now().add(Duration(days: id == 'future' ? 1 : -1)),
        },
    ];
    repo.rsvps = [
      for (final id in ['past', 'future', 'attended', 'cancelled'])
        {'eventId': id, 'cancelledAt': id == 'cancelled' ? repo.now() : null},
    ];
    repo.checkins = [
      {'eventId': 'attended', 'status': 'confirmed'},
    ];
    final rows = profileHistory(repo);
    expect(rows.length, 3);
    expect(rows.where((r) => r['attended'] == true).length, 1);
    expect(rows.where((r) => r['missed'] == true).map((r) => r['id']), [
      'past',
    ]);
    expect(rows.first['id'], 'future');
  });
  for (final size in [
    const Size(393, 852),
    const Size(360, 640),
    const Size(800, 1280),
  ]) {
    testWidgets(
      'reference profile has three current forms and accessible settings at $size',
      (tester) async {
        tester.view.physicalSize = size;
        tester.view.devicePixelRatio = 1;
        tester.platformDispatcher.textScaleFactorTestValue = size.width == 360
            ? 1.5
            : 1;
        addTearDown(tester.view.resetPhysicalSize);
        addTearDown(tester.view.resetDevicePixelRatio);
        addTearDown(tester.platformDispatcher.clearTextScaleFactorTestValue);
        await tester.pumpWidget(
          ParticipantApp(
            repository: FakeParticipantRepository(),
            initialPage: 'profile',
            cameraEnabled: false,
          ),
        );
        await tester.pumpAndSettle();
        expect(find.text('FORMS'), findsOneWidget);
        expect(find.text('RECENT SESSIONS'), findsOneWidget);
        expect(find.text('Current'), findsNWidgets(3));
        expect(find.text('Sessions attended'), findsOneWidget);
        expect(find.text('Counted in, did not attend'), findsOneWidget);
        expect(find.byType(AppBar), findsNothing);
        expect(find.byKey(const Key('profile-sign-forms')), findsOneWidget);
        await tester.scrollUntilVisible(
          find.text('Update safety details'),
          250,
          scrollable: find.byType(Scrollable).first,
        );
        expect(find.text('Update safety details'), findsOneWidget);
        expect(find.byType(ExpansionTile), findsNothing);
        await tester.scrollUntilVisible(
          find.text('Sign-in methods'),
          150,
          scrollable: find.byType(Scrollable).first,
        );
        expect(find.text('Sign-in methods'), findsOneWidget);
        expect(tester.takeException(), isNull);
      },
    );
  }
}
