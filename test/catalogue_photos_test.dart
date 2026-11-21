import 'dart:typed_data';

import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:image/image.dart' as img;
import 'package:rally4ever/participant/catalogue.dart';
import 'package:rally4ever/participant/catalogue_photos.dart';
import 'package:rally4ever/participant/catalogue_admin.dart';
import 'package:rally4ever/shared/logo.dart';
import 'package:timezone/data/latest.dart' as tz;

import 'support/fake_participant.dart';

void main() {
  test('session photo then canonical venue then neutral placeholder, never another venue', () {
    final venues = [
      {'id': 'manly', 'photoUrl': 'https://example.test/manly.jpg'},
      {'id': 'chatswood', 'photoUrl': 'https://example.test/chatswood.jpg'},
    ];
    final session = {
      'venueId': 'manly',
      'photoUrl': 'https://example.test/session.jpg',
      'venue': {'id': 'manly', 'photoUrl': 'https://example.test/stale.jpg'},
    };
    expect(
      cataloguePhotoUrl(session, venues),
      'https://example.test/session.jpg',
    );
    expect(
      cataloguePhotoUrl({...session, 'photoUrl': ''}, venues),
      'https://example.test/manly.jpg',
    );
    expect(
      cataloguePhotoUrl({...session, 'photoMode': 'venue'}, venues),
      'https://example.test/manly.jpg',
    );
    expect(
      cataloguePhotoUrl({...session, 'photoMode': 'none'}, venues),
      isNull,
    );
    expect(
      cataloguePhotoUrl({
        'venueId': 'unknown',
        'venue': {'name': 'Unknown'},
      }, venues),
      isNull,
    );
  });
  for (final size in [
    [2000, 1000],
    [1000, 2000],
    [320, 200],
  ]) {
    test('JPEG resize limits long side and preserves aspect for $size', () {
      final source = Uint8List.fromList(
        img.encodePng(img.Image(width: size[0], height: size[1])),
      );
      final bytes = resizeCataloguePhoto(source),
          decoded = img.decodeJpg(bytes)!;
      expect(decoded.width, lessThanOrEqualTo(1600));
      expect(decoded.height, lessThanOrEqualTo(1600));
      expect(decoded.width / decoded.height, closeTo(size[0] / size[1], .01));
      expect(bytes.length, lessThanOrEqualTo(5 * 1024 * 1024));
      if (size[0] < 1600 && size[1] < 1600) expect(decoded.width, size[0]);
    });
  }
  test(
    'invalid image fails clearly',
    () => expect(
      () => resizeCataloguePhoto(Uint8List.fromList([1, 2, 3])),
      throwsFormatException,
    ),
  );
  test('admin times are readable and in the session timezone', () {
    tz.initializeTimeZones();
    expect(
      adminSessionTime({
        'startsAt': '2026-11-19T13:12:33.702+11:00',
        'timezone': 'Australia/Sydney',
      }),
      'Thu 19 Nov, 1:12 pm',
    );
  });
  testWidgets(
    'missing session photo shows the brand symbol and admin controls',
    (tester) async {
      await tester.pumpWidget(
        MaterialApp(
          home: Scaffold(
            body: CataloguePhotoControl(
              repository: FakeParticipantRepository(),
              record: {'id': 'event-1', 'revision': 1},
              kind: 'session',
            ),
          ),
        ),
      );
      await tester.pumpAndSettle();
      expect(find.byType(Logo), findsOneWidget);
      expect(find.text('Change photo'), findsOneWidget);
      expect(find.text('Use venue photo'), findsOneWidget);
      expect(find.text('Remove photo'), findsOneWidget);
      expect(find.byType(Image), findsNothing);
    },
  );
}
