import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:latlong2/latlong.dart';
import 'package:rally4ever/participant/app.dart';
import 'package:rally4ever/participant/catalogue.dart';
import 'package:rally4ever/participant/repository.dart';

import 'support/fake_participant.dart';

List<Record> locations() => [
  for (final entry in [
    ('Ashfield', -33.892358, 151.122487, 'active'),
    ('Armidale', -30.5, 151.649994, 'active'),
    ('Grafton', -29.644989, 152.922581, 'active'),
    ('Walgett', -30.024685, 148.114412, 'draft'),
  ])
    {
      'id': entry.$1,
      'name': '${entry.$1} Tennis',
      'status': entry.$4,
      'sport': 'tennis',
      'venue': {
        'name': '${entry.$1} Courts',
        'address': 'Courts',
        'suburb': entry.$1,
        'postcode': '2000',
        'state': 'NSW',
        'lat': entry.$2,
        'lng': entry.$3,
      },
      'scheduleText': 'Weekly',
      'timezone': 'Australia/Sydney',
      'registrationStatus': 'open',
      'capacity': null,
    },
];
void main() {
  test('programs with zero sessions have separate discoverable markers and preserve radius/publication filters', () {
    final now = DateTime(2026, 11, 22), programs = locations();
    const rose = LatLng(-33.871, 151.271);
    expect(
      undatedProgramRecords(
        programs,
        [],
        now: now,
        centre: rose,
      ).map((p) => p['id']),
      ['Ashfield'],
    );
    expect(
      undatedProgramRecords(
        programs,
        [],
        now: now,
        centre: rose,
        radiusKm: double.infinity,
      ).map((p) => p['id']),
      ['Ashfield', 'Armidale', 'Grafton'],
    );
    expect(
      undatedProgramRecords(
        programs,
        [],
        now: now,
        centre: rose,
        sport: 'Pickleball',
      ),
      isEmpty,
    );
    final sessions = [
      {
        'id': 'dated',
        'programId': 'Ashfield',
        'status': 'published',
        'endsAt': now.add(const Duration(days: 1)),
      },
    ];
    expect(
      undatedProgramRecords(programs, sessions, now: now, centre: rose),
      isEmpty,
    );
    sessions.first['status'] = 'cancelled';
    expect(
      undatedProgramRecords(programs, sessions, now: now, centre: rose).length,
      1,
    );
    programs.first['deletedAt'] = now;
    expect(
      undatedProgramRecords(programs, [], now: now, centre: rose),
      isEmpty,
    );
  });
  testWidgets(
    'map shows program location with zero dated sessions and All Australia reveals distant published programs',
    (tester) async {
      tester.view.physicalSize = const Size(393, 852);
      tester.view.devicePixelRatio = 1;
      addTearDown(tester.view.resetPhysicalSize);
      addTearDown(tester.view.resetDevicePixelRatio);
      final repo = FakeParticipantRepository()
        ..events = []
        ..programs = locations()
        ..locationStatus = 'granted'
        ..deviceLocation = {'lat': -33.871, 'lng': 151.271};
      await tester.pumpWidget(
        ParticipantApp(
          repository: repo,
          initialPage: 'map',
          cameraEnabled: false,
          mapTilesEnabled: false,
        ),
      );
      await tester.pumpAndSettle();
      expect(find.byKey(const Key('program-marker-Ashfield')), findsOneWidget);
      expect(find.byKey(const Key('program-marker-Grafton')), findsNothing);
      expect(find.text('0 sessions nearby'), findsOneWidget);
      expect(find.textContaining('1 program awaiting dates'), findsOneWidget);
      await tester.tap(find.byKey(const Key('map-browse-scope')));
      await tester.pumpAndSettle();
      for (final id in ['Ashfield', 'Armidale', 'Grafton']) {
        expect(find.byKey(Key('program-marker-$id')), findsOneWidget);
      }
      expect(find.byKey(const Key('program-marker-Walgett')), findsNothing);
      expect(find.text('0 sessions across Australia'), findsOneWidget);
      expect(find.textContaining('3 programs awaiting dates'), findsOneWidget);
      expect(repo.events, isEmpty);
      expect(tester.takeException(), isNull);
      await tester.tap(find.byKey(const Key('program-marker-Grafton')));
      await tester.pumpAndSettle();
      expect(find.text('Grafton Tennis'), findsOneWidget);
      await tester.scrollUntilVisible(
        find.textContaining('No dated sessions'),
        200,
        scrollable: find.byType(Scrollable).first,
      );
      expect(find.textContaining('No dated sessions'), findsOneWidget);
    },
  );
  testWidgets(
    'published program locations arriving after map startup become visible',
    (tester) async {
      final repo = FakeParticipantRepository()
        ..events = []
        ..programs = []
        ..locationStatus = 'granted'
        ..deviceLocation = {'lat': -33.871, 'lng': 151.271};
      await tester.pumpWidget(
        ParticipantApp(
          repository: repo,
          initialPage: 'map',
          cameraEnabled: false,
          mapTilesEnabled: false,
        ),
      );
      await tester.pumpAndSettle();
      expect(find.byKey(const Key('program-marker-Ashfield')), findsNothing);
      repo.programs = locations();
      repo.notifyListeners();
      await tester.pumpAndSettle();
      expect(find.byKey(const Key('program-marker-Ashfield')), findsOneWidget);
      expect(find.text('0 sessions nearby'), findsOneWidget);
      expect(tester.takeException(), isNull);
    },
  );
}
