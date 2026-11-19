import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:flutter_map/flutter_map.dart';
import 'package:latlong2/latlong.dart';
import 'package:rally4ever/participant/app.dart';
import 'package:rally4ever/participant/catalogue.dart';
import 'package:rally4ever/participant/repository.dart';

import 'support/fake_participant.dart';

List<Record> demoSessions(DateTime now) => [
  for (final v in [
    ('epping', -33.772, 151.081),
    ('parramatta', -33.815, 150.999),
    ('bondi', -33.8926, 151.2511),
  ])
    {
      'id': v.$1,
      'eventId': v.$1,
      'name': v.$1,
      'sport': 'tennis',
      'status': 'published',
      'startsAt': now.add(const Duration(hours: 1)),
      'endsAt': now.add(const Duration(hours: 2)),
      'venue': {'name': v.$1, 'lat': v.$2, 'lng': v.$3},
      'coachUids': [],
      'requiredFormIds': [],
    },
];
void main() {
  test('scanner accepts only the existing and owned Hosting QR origins', () {
    expect(
      CheckInLink.parse(
        'https://rally4ever-checkin-3adaf.web.app/c/DEMO?k=0123456789012345678901234567890123456789012',
      ).eventCode,
      'DEMO',
    );
    expect(
      () => CheckInLink.parse(
        'https://evil.web.app/c/DEMO?k=0123456789012345678901234567890123456789012',
      ),
      throwsFormatException,
    );
  });
  test('Rose Bay GPS sorts Bondi before Epping and Parramatta and applies the same radius', () {
    final now = DateTime(2026, 11, 20), events = demoSessions(now);
    const rose = LatLng(-33.871, 151.271);
    final rows = nearbySessionRecords(events, now: now, centre: rose);
    expect(rows.map((e) => e['id']), ['bondi', 'epping', 'parramatta']);
    expect(
      sessionDistanceLabel(rows.first, rose),
      matches(RegExp(r'^[23]\.\d km$')),
    );
    expect(
      nearbySessionRecords(
        events,
        now: now,
        centre: rose,
        radiusKm: 5,
      ).map((e) => e['id']),
      ['bondi'],
    );
  });
  testWidgets(
    'map marker count uses GPS session query and includes a separate live blue dot',
    (tester) async {
      final repo = FakeParticipantRepository()
        ..locationStatus = 'granted'
        ..deviceLocation = {'lat': -33.871, 'lng': 151.271};
      repo.events = demoSessions(repo.now());
      repo.profile['postcode'] = '2121';
      await tester.pumpWidget(
        ParticipantApp(
          repository: repo,
          initialPage: 'map',
          cameraEnabled: false,
          mapTilesEnabled: false,
        ),
      );
      await tester.pumpAndSettle();
      expect(find.text('3 sessions nearby'), findsOneWidget);
      expect(find.byKey(const Key('user-location-dot')), findsOneWidget);
      final markers = tester
          .widget<MarkerLayer>(find.byType(MarkerLayer))
          .markers;
      expect(markers.length, 4);
      expect(find.byKey(const Key('centre-on-me')), findsOneWidget);
      await tester.tap(find.byTooltip('Back'));
      await tester.pumpAndSettle();
      final texts = find.byKey(const Key('event-bondi'));
      expect(texts, findsOneWidget);
      final yBondi = tester.getTopLeft(texts).dy;
      final yEpping = tester
          .getTopLeft(find.byKey(const Key('event-epping')))
          .dy;
      expect(yBondi, lessThan(yEpping));
      expect(find.byKey(const Key('distance-bondi')), findsOneWidget);
      expect(
        tester.widget<NavigationBar>(find.byType(NavigationBar)).selectedIndex,
        0,
      );
      await tester.pumpWidget(const SizedBox());
      repo.dispose();
    },
  );
  testWidgets(
    'returning through login selects Play and safety Back returns to Me',
    (tester) async {
      final repo = FakeParticipantRepository();
      await tester.pumpWidget(
        ParticipantApp(
          repository: repo,
          initialPage: 'profile',
          cameraEnabled: false,
          mapTilesEnabled: false,
        ),
      );
      await tester.pumpAndSettle();
      repo.uid = null;
      repo.notifyListeners();
      await tester.pumpAndSettle();
      repo.uid = 'participant-1';
      repo.notifyListeners();
      await tester.pumpAndSettle();
      expect(
        tester.widget<NavigationBar>(find.byType(NavigationBar)).selectedIndex,
        0,
      );
      expect(
        tester
            .widget<ChoiceChip>(find.widgetWithText(ChoiceChip, 'All'))
            .selected,
        true,
      );
      await tester.tap(find.text('Me'));
      await tester.pumpAndSettle();
      await tester.scrollUntilVisible(
        find.text('Update safety details'),
        250,
        scrollable: find.byType(Scrollable).first,
      );
      await tester.tap(find.text('Update safety details'));
      await tester.pumpAndSettle();
      await tester.tap(find.byTooltip('Back'));
      await tester.pumpAndSettle();
      expect(find.text('Profile & preferences'), findsOneWidget);
      expect(
        tester.widget<NavigationBar>(find.byType(NavigationBar)).selectedIndex,
        3,
      );
      await tester.pumpWidget(const SizedBox());
      repo.dispose();
    },
  );
}
